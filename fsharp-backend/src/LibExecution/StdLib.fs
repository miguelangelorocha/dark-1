module LibExecution.StdLib

open FSharp.Control.Tasks
open Runtime
open Interpreter

let fns: List<BuiltInFn> = LibString.fns
// [ { name = FnDesc.stdFnDesc "Int" "range" 0
//     parameters =
//       [ param "list" (TList(TVariable("a"))) "The list to be operated on"
//         param "fn" (TFn([ TVariable("a") ], TVariable("b"))) "Function to be called on each member" ]
//     returnType = retVal (TList(TInt)) "List of ints between lowerBound and upperBound"
//     fn =
//       (function
//       | _, [ DInt lower; DInt upper ] ->
//           List.map DInt [ lower .. upper ]
//           |> DList
//           |> Plain
//
//       | _ -> Error()) }
//   { name = FnDesc.stdFnDesc "List" "map" 0
//     parameters =
//       [ param "list" (TList(TVariable("a"))) "The list to be operated on"
//         param "fn" (TFn([ TVariable("a") ], TVariable("b"))) "Function to be called on each member" ]
//     returnType =
//       (retVal
//         (TList(TVariable("b")))
//          "A list created by the elements of `list` with `fn` called on each of them in order")
//     fn =
//       (function
//       | env, [ DList l; DLambda (st, [ var ], body) ] ->
//           Ok
//             (Task
//               (task {
//                 let! result =
//                   map_s l (fun dv ->
//                     let st = st.Add(var, dv)
//                     eval env st body)
//
//                 return (result |> Dval.toDList)
//                }))
//       | _ -> Error()) }
//   { name = (FnDesc.stdFnDesc "Int" "%" 0)
//     parameters =
//       [ param "a" TInt "Numerator"
//         param "b" TInt "Denominator" ]
//     returnType = (retVal TInt "Returns the modulus of a / b")
//     fn =
//       (function
//       | env, [ DInt a; DInt b ] ->
//           try
//             (Plain(DInt(a % b)))
//           with _ -> (Plain(Dval.int 0))
//       | _ -> Error()) }
//   { name = (FnDesc.stdFnDesc "Int" "==" 0)
//     parameters =
//       [ param "a" TInt "a"
//         param "b" TInt "b" ]
//     returnType =
//       (retVal
//         TBool
//          "True if structurally equal (they do not have to be the same piece of memory, two dicts or lists or strings with the same value will be equal), false otherwise")
//     fn =
//       (function
//       | env, [ DInt a; DInt b ] -> (Plain(DBool(a = b)))
//       | _ -> Error()) }
//   { name = (FnDesc.stdFnDesc "Int" "toString" 0)
//     parameters = [ param "a" TInt "value" ]
//     returnType = (retVal TString "Stringified version of a")
//     fn =
//       (function
//       | env, [ DInt a ] -> (Plain(DStr(a.ToString())))
//
//       | _ -> Error()) }
//   { name = (FnDesc.stdFnDesc "HttpClient" "get" 0)
//     parameters = [ param "url" TString "URL to fetch" ]
//     returnType = (retVal TString "Body of response")
//     fn =
//       (function
//       | env, [ DStr url ] ->
//           try
//             Ok
//               (Task
//                 (task {
//                   let! response = FSharp.Data.Http.AsyncRequestString(url)
//                   return DStr(response)
//                  }))
//           with e ->
//             printfn "error in HttpClient::get: %s" (e.ToString())
//             Error()
//       | _ -> Error()) } ]
//
