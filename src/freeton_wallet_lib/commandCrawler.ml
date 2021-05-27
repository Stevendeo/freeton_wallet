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

let cmd =

  let dropdb = ref false in
  let account = ref None in
  let action = ref Crawler.Crawler in
  EZCMD.sub
    "crawler"
    (fun () ->
       Crawler.action ~dropdb:!dropdb ~account:!account ~action:!action
    )
    ~doc: "Crawl all transactions to an address and fill a psql database"
    ~args:[
      [], Arg.Anon (0, fun addr -> account := Some addr),
      EZCMD.info ~docv:"ACCOUNT" "Account to crawl" ;

      [ "start" ], Arg.Unit (fun () -> action := Start),
      EZCMD.info "Start with a manager process to restart automatically" ;

      [ "status" ], Arg.Unit (fun () -> action := Status),
      EZCMD.info "Check if a manager process and crawler are running" ;

      [ "stop" ], Arg.Unit (fun () -> action := Stop),
      EZCMD.info "Stop the manager process and the crawler" ;

      [ "dropdb" ], Arg.Set dropdb,
      EZCMD.info "Drop the previous database" ;

    ]
    ~man:[
      `S "DESCRIPTION";
      `Blocks [
        `P "This command will crawl the blockchain and fill a \
            PostgresQL database with all events related to the \
            contract given in argument. The created database has the \
            same name as the account.";
        `P "This command can run as a service, using the --start \
            command to launch a manager program (that will not detach \
            itself, however), --status to check the current status \
            (running or not) and --stop to stop the process and its \
            manager.";
        `P "A simple session looks like:";
        `Pre {|sh> ft crawler myapp --start &> daemon.log &
sh> psql myapp
SELECT * FROM freeton_events;
serial|                              msg_id                              |      event_name       |           event_args                            |    time    | tr_lt
    1 | ec026489c0eb2071b606db0c7e05e5a76c91f4b02c2b66af851d56d5051be8bd | OrderStateChanged     | {"order_id":"31","state_count":"1","state":"1"} | 1620744626 | 96
SELECT * FROM freeton_transactions;
^D
sh> ft crawler myapp --stop
|};
      ];
      `S "ERRORS";
      `Blocks [
        `P "The crawler may fail connecting to the database. You can \
            use PGHOST to set the hostname of the database, or the \
            directory of unix sockets (default is \
            /var/run/postgresql). You can use PGPORT for the port \
            (default is 5432).";
        `P {|The crawler may also fail for authorizations (something like FATAL: 28000: role USER does not exist ). In such a case, you need to configure postgresql to allow your role (<user> is your username):|};
        `Pre {|
     sh> sudo -i -u postgres
     root> psql
     CREATE USER <user>;
     ALTER ROLE <user> CREATEDB;
|}


      ];
    ]
