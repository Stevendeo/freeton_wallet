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
open EZCMD.TYPES

open Types

let is_multisig_contract = function
  | "SafeMultisigWallet"
  | "SetcodeMultisigWallet"
  | "SetcodeMultisigWallet2"
    -> true
  | _ -> false

let check_key_contract key =
  match key.key_account with
  | Some { acc_contract = Some acc_contract ; _ } ->
      if is_multisig_contract acc_contract then
        acc_contract
      else
        Error.raise "Account's contract %S is not multisig" acc_contract;

      (* Account's contract is not set, let's use the minimal common ABI *)
  | _ ->
      "SafeMultisigWallet"

let send_transfer ~account ?src ~dst ~amount ?(bounce=false) ?(args=[])
    ?(wait=false) () =
  let config = Config.config () in
  let net = Config.current_network config in

  let src = match src with
      None -> account
    | Some src -> src
  in
  let src_key = Misc.find_key_exn net src in

  let account_addr, account_contract =
    match Misc.is_address account with
    | Some address -> address, "SafeMultisigWallet"
    | None ->
        let account_key = Misc.find_key_exn net account in
        let account_addr = Misc.get_key_address_exn account_key in
        let account_contract = check_key_contract account_key in
        ( account_addr, account_contract )
  in
  let dst_addr = Utils.address_of_account config dst in
  let dst_addr = Misc.raw_address dst_addr in

  let nanotokens, allBalance =
    if amount = "all" then
      2_000_000L, (* MIN_VALUE is 1e06 in SetcodeMultisigWallet2 *)
      true
    else
      Misc.nanotokens_of_string amount, false
  in

  begin match Utils.get_account_info config account_addr with
    | Some (account_exists, account_balance) ->
        if not account_exists then
          Error.raise "Account %s does not exist yet." account ;
        if ( not allBalance ) && Z.of_int64 nanotokens >= account_balance then
          Error.raise
            "Balance %s nanotons of account %s is smaller than transferred amount %s"
            (Z.to_string account_balance) account amount
    | None ->
        Error.raise "Account %s does not exist yet." account
  end;

  let dst_exists = match Utils.get_account_info config dst_addr with
      Some (dst_exists, _ ) -> dst_exists
    | None -> false
  in
  if bounce && not dst_exists then
    Error.raise "Destination does not exist. Use --parrain option";

  let args = match args with
    | [ meth ; params ] -> Some ( meth, params )
    | [ meth ] -> Some ( meth, "{}" )
    | [] -> None
    | _ ->
        Error.raise "Too many params arguments"
  in
  let payload = match args with
    | Some ( meth , params ) ->
        let dst_key = Misc.find_key_exn net dst in
        let dst_contract = Misc.get_key_contract_exn dst_key in
        let abi_file = Misc.get_contract_abifile dst_contract in
        let abi = EzFile.read_file abi_file in
        Ton_sdk.ABI.encode_body ~abi ~meth ~params
    | None -> ""
  in

  let meth, params =
    if allBalance then
      let meth = "sendTransaction" in
      let params = Printf.sprintf
          {|{"dest":"%s","value":0,"bounce":%b,"flags":128,"payload":"%s"}|}
          dst_addr
          bounce
          payload
      in
      Printf.eprintf "Warning: 'all' balance only works with one-custodian multisigs\n%!";
      meth, params
    else
      let meth = "submitTransaction" in
      let params = Printf.sprintf
          {|{"dest":"%s","value":%Ld,"bounce":%b,"allBalance":%b,"payload":"%s"}|}
          dst_addr
          nanotokens
          bounce
          allBalance
          payload
      in
      meth, params
  in
  Utils.call_contract config ~contract:account_contract
    ~address:account_addr
    ~meth ~params
    ~local:false
    ~src:src_key
    ~wait
    ()

let action account args ~amount ~dst ~bounce ~src ~wait =

  let config = Config.config () in

  let account = match account with
    | None ->
        Error.raise "The argument --from ACCOUNT is mandatory"
    | Some account -> account
  in

  Subst.with_substituted_list config args (fun args ->
      match dst with
      | Some dst ->
          send_transfer ~account ?src ~dst ~bounce ~amount ~args ~wait ()
      | _ ->
          Error.raise "The argument --to ACCOUNT is mandatory"
    )

let cmd =
  let account = ref None in
  let args = ref [] in
  let dst = ref None in
  let bounce = ref true in
  let src = ref None in
  let wait = ref false in

  EZCMD.sub
    "multisig transfer"
    (fun () ->
       match !args with
       | [] -> Error.raise "You must provide the amount to transfer"
       | amount :: args ->
           action !account
             args
             ~amount
             ~dst:!dst
             ~bounce:!bounce
             ~src:!src
             ~wait:!wait
    )
    ~args:
      [
        [], Arg.Anons (fun list -> args := list),
        EZCMD.info "Generic arguments" ;

        [ "from" ], Arg.String (fun s -> account := Some s),
        EZCMD.info ~docv:"ACCOUNT" "The source of the transfer";

        [ "src" ], Arg.String (fun s -> src := Some s),
        EZCMD.info ~docv:"ACCOUNT"
          "The custodian signing the multisig transfer";

        [ "wait" ], Arg.Set wait,
        EZCMD.info "Wait for all transactions to finish";

        [ "parrain" ], Arg.Clear bounce,
        EZCMD.info " Transfer to inactive account";

        [ "bounce" ], Arg.Bool (fun b -> bounce := b),
        EZCMD.info "BOOL Transfer to inactive account";

        [ "to" ], Arg.String (fun s -> dst := Some s),
        EZCMD.info ~docv:"ACCOUNT" "Target of a transfer";

      ]
    ~doc: "Manage a multisig-wallet (create, confirm, send)"
    ~man:[
      `S "DESCRIPTION";
      `P "This command is used to manage a multisig wallet, i.e. create the wallet, send tokens and confirm transactions.";

      `S "CREATE MULTISIG";
      `P "Create an account and get its address:";
      `Pre {|# ft account --create my-account
# ft genaddr my-account|};
      `P "Backup the account info off-computer.";
      `P "The second command will give you an address in 0:XXX format. Send some tokens on the address to be able to deploy the multisig.";
      `P "Check its balance with:";
      `Pre {|# ft account my-account|};
      `P "Then, to create a single-owner multisig:";
      `Pre {|# ft multisig -a my-account --create|} ;
      `P "To create a multi-owners multisig:";
      `Pre {|# ft multisig -a my-account --create owner2 owner3 owner4|} ;
      `P "To create a multi-owners multisig with 2 signs required:";
      `Pre {|# ft multisig -a my-account --create owner2 owner3 --req 2|} ;
      `P "To create a multi-owners multisig not self-owning:";
      `Pre {|# ft multisig -a my-account --create owner1 owner2 owner3 --not-owner|} ;

      `P "Verify that it worked:";
      `Pre {|# ft account my-account -v|};

      `S "GET CUSTODIANS";
      `P "To get the list of signers:";
      `Pre {|# ft multisig -a my-account --custodians"|};

      `S "SEND TOKENS";
      `P "Should be like that:";
      `Pre {|# ft multisig -a my-account --transfer 100.000 --to other-account|};
      `P "If the target is not an active account:";
      `Pre {|# ft multisig -a my-account --transfer 100.000 --to other-account --parrain|};
      `P "To send all the balance:";
      `Pre {|# ft multisig -a my-account --transfer all --to other-account|};

      `S "CALL WITH TOKENS";
      `P "Should be like that:";
      `Pre {|# ft multisig -a my-account --transfer 100 --to contract set '{ "x": "100" }|};

      `S "LIST WAITING TRANSACTIONS";
      `P "Display transactions waiting for confirmations:";
      `Pre {|# ft multisig -a my-account --waiting|};

      `S "CONFIRM TRANSACTION";
      `P "Get the transaction ID from above, and use:";
      `Pre {|# ft multisig -a my-account --confirm TX_ID|};
    ]