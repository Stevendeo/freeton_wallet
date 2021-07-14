(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2021 OCamlPro SAS                                       *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Lesser General    *)
(*  Public License version 2.1, with the special exception on linking     *)
(*  described in the LICENSE.md file in the root directory.               *)
(*                                                                        *)
(*                                                                        *)
(**************************************************************************)

open Ezcmd.V2
open Types
(* open EzFile.OP *)

let container_of_node local_node =
  Printf.sprintf "local-node-%d" local_node.local_port

let action () =
  let config = Config.config () in
  let node = Config.current_node config in
  match node.node_local with
  | None ->
      Error.raise "cannot manage remote node %S" node.node_name
  | Some local_node ->
      Misc.call [ "docker"; "stop" ; container_of_node local_node ]

let cmd =
  EZCMD.sub
    "node stop"
    (fun () ->
       action ()
    )
    ~args: [
    ]
    ~doc: "Stop the local node of a sandbox switch"
    ~man:[
      `S "DESCRIPTION";
      `P "This command can be used to stop the local node of a sandbox \
          network running TONOS SE"
    ]
