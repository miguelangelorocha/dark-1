open Core_kernel
open Libexecution
open Libcommon
open Types
open Types.RuntimeT

let init () =
  Libs.init Builtin_libs.fns ;
  print_endline "libfrontend reporting in"


type handler_list = HandlerT.handler list [@@deriving yojson]

type input_vars = (string * dval) list (* list of vars *) [@@deriving of_yojson]

(* We bring in our own definition because the deserializer is in Dval but the
 * definition is in Types, and that's challenging *)

type our_tipe = tipe

let our_tipe_of_yojson json = Dval.unsafe_tipe_of_yojson json

type our_col = string or_blank * our_tipe or_blank [@@deriving of_yojson]

type our_db_migration =
  { starting_version : int
  ; version : int
  ; state : DbT.db_migration_state
  ; rollforward : fluid_expr
  ; rollback : fluid_expr
  ; cols : our_col list }
[@@deriving of_yojson]

type our_db =
  { tlid : tlid
  ; name : string or_blank
  ; cols : our_col list
  ; version : int
  ; old_migrations : our_db_migration list
  ; active_migration : our_db_migration option }
[@@deriving of_yojson]

let convert_col ((name, tipe) : our_col) : DbT.col = (name, tipe)

let convert_migration (m : our_db_migration) : DbT.db_migration =
  { starting_version = m.starting_version
  ; version = m.version
  ; state = m.state
  ; rollforward = m.rollforward
  ; rollback = m.rollback
  ; cols = List.map ~f:convert_col m.cols }


let convert_db (db : our_db) : DbT.db =
  { tlid = db.tlid
  ; name = db.name
  ; cols = List.map ~f:convert_col db.cols
  ; version = db.version
  ; old_migrations = List.map ~f:convert_migration db.old_migrations
  ; active_migration = Option.map ~f:convert_migration db.active_migration }


type handler_analysis_param =
  { handler : HandlerT.handler
  ; trace_id : Analysis_types.traceid
  ; trace_data : Analysis_types.trace_data
        (* dont use a trace as this isn't optional *)
  ; dbs : our_db list
  ; user_fns : user_fn list
  ; user_tipes : user_tipe list
  ; secrets : secret list }
[@@deriving of_yojson]

type function_analysis_param =
  { func : user_fn
  ; trace_id : Analysis_types.traceid
  ; trace_data : Analysis_types.trace_data
        (* dont use a trace as this isn't optional *)
  ; dbs : our_db list
  ; user_fns : user_fn list
  ; user_tipes : user_tipe list
  ; secrets : secret list }
[@@deriving of_yojson]

type analysis_envelope = uuid * Analysis_types.analysis [@@deriving to_yojson]

let load_from_trace
    (results : Analysis_types.function_result list)
    (tlid, fnname, caller_id)
    (args : dval list) : (dval * Time.t) option =
  let hashes =
    Dval.supported_hash_versions
    |> List.map ~f:(fun key -> (id_of_int key, Dval.hash key args))
    |> IDMap.of_alist_exn
  in
  results
  |> List.filter_map ~f:(fun (rfnname, rcaller_id, hash, hash_version, dval) ->
         if fnname = rfnname
            && caller_id = rcaller_id
            && hash = IDMap.find_exn hashes (id_of_int hash_version)
         then Some dval
         else None)
  |> List.hd
  (* We don't use the time, so just hack it to get the interface right. *)
  |> Option.map ~f:(fun dv -> (dv, Time.now ()))


(* We can sometimes get infinity/NaN in analysis results. While the Dark
 * language isn't intended to have them, we haven't actually managed to
 * eradicate them from the runtime, and so we need to send them back to the
 * client. However, since JSON doesn't support Infinity/NaN, the client JSON
 * parser crashes. So instead we encode them specially, and also support
 * decoding them in the client dval Decoder (client/src/Decoder.ml). *)
let rec clean_yojson (json : Yojson.Safe.t) : Yojson.Safe.t =
  match json with
  | `Float f ->
      if Float.is_nan f
      then `Assoc [("type", `String "float"); ("value", `String "NaN")]
      else if Float.is_finite f
      then `Float f
      else `Assoc [("type", `String "float"); ("value", `String "Infinity")]
  | `List l ->
      `List (List.map ~f:clean_yojson l)
  | `Tuple l ->
      `Tuple (List.map ~f:clean_yojson l)
  | `Assoc o ->
      `Assoc (List.map ~f:(fun (k, v) -> (k, clean_yojson v)) o)
  | a ->
      a


let perform_analysis
    ~(tlid : tlid)
    ~(dbs : our_db list)
    ~(user_fns : user_fn list)
    ~(user_tipes : user_tipe list)
    ~(secrets : secret list)
    ~(trace_id : RuntimeT.uuid)
    ~(trace_data : Analysis_types.trace_data)
    ast =
  let dbs : DbT.db list = List.map ~f:convert_db dbs in
  let execution_id = Types.id_of_int 1 in
  let input_vars = trace_data.input in
  let function_results = trace_data.function_results in
  Log.add_log_annotations
    [ ("execution_id", `String (Types.string_of_id execution_id))
    ; ("tlid", `String (Types.string_of_id tlid)) ]
    (fun _ ->
      ( trace_id
      , Execution.analyse_ast
          ast
          ~tlid
          ~execution_id
          ~account_id:(Util.create_uuid ())
          ~canvas_id:(Util.create_uuid ())
          ~input_vars
          ~dbs
          ~user_fns
          ~user_tipes
          ~package_fns:[]
          ~secrets
          ~load_fn_result:(load_from_trace function_results)
          ~load_fn_arguments:Execution.load_no_arguments )
      |> analysis_envelope_to_yojson
      |> clean_yojson
      |> Yojson.Safe.to_string)


let perform_handler_analysis (str : string) : string =
  let {handler; dbs; user_fns; user_tipes; trace_id; trace_data; secrets} =
    str
    |> Yojson.Safe.from_string
    |> handler_analysis_param_of_yojson
    |> Result.ok_or_failwith
  in
  perform_analysis
    ~tlid:handler.tlid
    ~dbs
    ~user_fns
    ~user_tipes
    ~secrets
    ~trace_id
    ~trace_data
    handler.ast


let perform_function_analysis (str : string) : string =
  let {func; dbs; user_fns; user_tipes; trace_id; trace_data; secrets} =
    str
    |> Yojson.Safe.from_string
    |> function_analysis_param_of_yojson
    |> Result.ok_or_failwith
  in
  perform_analysis
    ~tlid:func.tlid
    ~dbs
    ~user_fns
    ~user_tipes
    ~secrets
    ~trace_id
    ~trace_data
    func.ast


open Js_of_ocaml

type js_string = Js.js_string Js.t

let () =
  init () ;
  Js.export
    "darkAnalysis"
    (object%js
       method performHandlerAnalysis
           (stringified_handler_analysis_param : js_string)
           : js_string Js.js_array Js.t =
         try
           stringified_handler_analysis_param
           |> Js.to_string
           |> perform_handler_analysis
           |> fun msg -> Js.array [|Js.string "success"; Js.string msg|]
         with e ->
           let error = Exception.to_string e in
           Js.array [|Js.string "failure"; Js.string error|]

       method performFunctionAnalysis
           (stringified_function_analysis_param : js_string)
           : js_string Js.js_array Js.t =
         try
           stringified_function_analysis_param
           |> Js.to_string
           |> perform_function_analysis
           |> fun msg -> Js.array [|Js.string "success"; Js.string msg|]
         with e ->
           let error = Exception.to_string e in
           Js.array [|Js.string "failure"; Js.string error|]
    end) ;
  ()
