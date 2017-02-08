open Std

type command =
    Command : string * Marg.docstring * 'args Marg.spec list * 'args *
              (Trace.t * Mconfig.t * Msource.t -> 'args -> json) -> command

let command name ?(doc="") ~spec ~default f =
  Command (name, doc, spec, default, f)

open Mconfig

let marg_position f = Marg.param "position"
    (function
      | "start" -> f `Start
      | "end" -> f `End
      | str -> match int_of_string str with
        | n -> f (`Offset n)
        | exception _ ->
          match
            let offset = String.index str ':' in
            let line = String.sub str ~pos:0 ~len:offset in
            let col = String.sub str ~pos:(offset+1)
                ~len:(String.length str - offset - 1) in
            `Logical (int_of_string line, int_of_string col)
          with
          | pos -> f pos
          | exception _ ->
            failwithf "expecting position, got %S. \
                       position can be start|end|<offset>|<line>:<col>, \
                       where offset, line and col are numbers, \
                       lines are indexed from 1."
              str
    )

let rec find_command name = function
  | [] -> raise Not_found
  | (Command (name', _, _, _, _) as command) :: xs ->
    if name = name' then
      command
    else find_command name xs

let run (trace, config, source as buffer) query =
  Logger.logj "New_commands.run" "query" (fun () -> Query_json.dump query);
  Mreader.with_ambient_reader trace config source @@ fun () ->
  let result = Query_commands.dispatch buffer query in
  let json = Query_json.json_of_response query result in
  Logger.logj "New_commands.run" "result" (fun () -> json);
  json

let all_commands = [

  command "case-analysis"
    ~doc:"case-analysis -start position -end position\n\t\
          TODO"
    ~spec: [
      ("-start",
       "<position> Where analysis starts",
       marg_position (fun startp (_startp,endp) -> (startp,endp))
      );
      ("-end",
       "<position> Where analysis ends",
       marg_position (fun endp (startp,_endp) -> (startp,endp))
      );
    ]
    ~default:(`Offset (-1), `Offset (-1))
    begin fun buffer -> function
      | (`Offset (-1), _) -> failwith "-start <pos> is mandatory"
      | (_, `Offset (-1)) -> failwith "-end <pos> is mandatory"
      | (startp, endp) ->
        run buffer (Query_protocol.Case_analysis (startp,endp))
    end
  ;

  command "complete-prefix"
    ~doc:"complete-prefix -position pos -prefix ident [-doc (y|n)]\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (txt,_pos,doc,typ) -> (txt,pos,doc,typ))
      );
      ("-doc",
       "<bool> Add docstring to entries (default is false)",
       Marg.bool (fun doc (txt,pos,_doc,typ) -> (txt,pos,doc,typ))
      );
      ("-prefix",
       "<string> Prefix to complete",
       Marg.param "string" (fun txt (_prefix,pos,doc,typ) -> (txt,pos,doc,typ))
      );
      ("-types",
       "<bool> Report type information (default is true)",
       Marg.bool (fun typ (txt,pos,doc,_typ) -> (txt,pos,doc,typ))
      );
    ]
    ~default:("",`None,false,true)
    begin fun buffer (txt,pos,doc,typ) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Complete_prefix (txt,pos,doc,typ))
    end
  ;

  command "document"
    ~doc:"document -position pos [-identifier ident]\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (ident,_pos) -> (ident,pos))
      );
      ("-identifier",
       "<string> Identifier",
       Marg.param "string" (fun ident (_ident,pos) -> (Some ident,pos))
      );
    ]
    ~default:(None,`None)
    begin fun buffer (ident,pos) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Document (ident, pos))
    end
  ;

  command "enclosing"
    ~doc:"enclosing -position pos\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos _pos -> pos)
      );
    ]
    ~default:`None
    begin fun buffer pos ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Enclosing pos)
    end
  ;

  command "errors"
    ~doc:"errors\n\t\
          TODO"
    ~spec:[]
    ~default:()
    begin fun buffer () ->
      run buffer (Query_protocol.Errors)
    end
  ;

  command "expand-prefix"
    ~doc:"expand-prefix -position pos -prefix ident\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (txt,_pos,typ) -> (txt,pos,typ))
      );
      ("-prefix",
       "<string> Prefix to complete",
       Marg.param "string" (fun txt (_prefix,pos,typ) -> (txt,pos,typ))
      );
      ("-types",
       "<bool> Report type information (default is false)",
       Marg.bool (fun typ (txt,pos,_typ) -> (txt,pos,typ))
      );
    ]
    ~default:("",`None,false)
    begin fun buffer (txt,pos,typ) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Expand_prefix (txt,pos,typ))
    end
  ;

  command "extension-list"
    ~doc:"extension-list [-status (all|enabled|disabled)]\n\t\
          List extensions"
    ~spec: [
      ("-status",
       "<all|enabled|disabled> Filter extensions",
       Marg.param "<all|enabled|disabled>"
         (fun status _status -> match status with
            | "all" -> `All
            | "enabled" -> `Enabled
            | "disabled" -> `Disabled
            | _ -> failwith "-status should be one of all, disabled or enabled"
         )
      );
    ]
    ~default:`All
    begin fun buffer status ->
      run buffer (Query_protocol.Extension_list status)
    end
  ;

  command "findlib-list"
    ~doc:"findlib-list\n\t\
          List all findlib packages"
    ~spec:[]
    ~default:()
    begin fun buffer () ->
      run buffer (Query_protocol.Findlib_list)
    end
  ;

  command "flags-list"
    ~doc:"flags-list\n\t\
          List flags"
    ~spec:[]
    ~default:()
    begin fun buffer () ->
      `List (List.map Json.string (Mconfig.flags_for_completion ()))
    end
  ;

  command "jump"
    ~doc:"locate -target target -position pos\n\t\
          TODO"
    ~spec: [
      ("-target",
       "<string> Entity to jump to",
       Marg.param "string" (fun target (_,pos) -> (target,pos))
      );
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (target,_pos) -> (target,pos))
      );
    ]
    ~default:("",`None)
    begin fun buffer (target,pos) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Jump (target,pos))
    end
  ;

  command "phrase"
    ~doc:"phrase -target [next|prev] -position pos\n\t\
          TODO"
    ~spec: [
      ("-target",
       "<next|prev> Entity to jump to",
       Marg.param "string" (fun target (_,pos) ->
           match target with
           | "next" -> (`Next,pos)
           | "prev" -> (`Prev,pos)
           | _ -> failwith "-target should be one of 'next' or 'prev'"
         )
      );
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (target,_pos) -> (target,pos))
      );
    ]
    ~default:(`Next,`None)
    begin fun buffer (target,pos) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Phrase (target,pos))
    end
  ;

  command "list-modules"
    ~doc:"list-modules -ext .ml -ext .mli ...\n\t\
          looks into project source paths for files with an extension \
          matching and prints the corresponding module name"
    ~spec:[
      ("-ext",
       "<extension> file extensions to look for",
       Marg.param "extension" (fun ext exts -> ext :: exts)
      )
    ]
    ~default:[]

    begin fun buffer extensions ->
      run buffer (Query_protocol.List_modules (List.rev extensions))
    end
  ;

  command "locate"
    ~doc:"locate -prefix prefix -position pos \
          [-look-for (interface|implementation)]\n\t\
          TODO"
    ~spec: [
      ("-prefix",
       "<string> Prefix to complete",
       Marg.param "string" (fun prefix (_,pos,kind) -> (Some prefix,pos,kind))
      );
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (prefix,_pos,kind) -> (prefix,pos,kind))
      );
      ("-look-for",
       "<interface|implementation> Prefer opening interface or implementation",
       Marg.param "<interface|implementation>"
         (fun kind (prefix,pos,_) -> match kind with
            | "mli" | "interface" -> (prefix,pos,`MLI)
            | "ml"  | "implementation" -> (prefix,pos,`ML)
            | str ->
              failwithf "expecting interface or implementation, got %S." str)
      );
    ]
    ~default:(None,`None,`MLI)
    begin fun buffer (prefix,pos,lookfor) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Locate (prefix,lookfor,pos))
    end
  ;

  command "occurrences"
    ~doc:"occurrences -identifier-at pos\n\t\
          TODO"
    ~spec: [
      ("-identifier-at",
       "<position> Position to complete",
       marg_position (fun pos _pos -> (`Ident_at pos))
      );
    ]
    ~default:`None
    begin fun buffer -> function
      | `None -> failwith "-identifier-at <pos> is mandatory"
      | `Ident_at pos ->
        run buffer (Query_protocol.Occurrences (`Ident_at pos))
    end
  ;

  command "outline"
    ~doc:"outline\n\t\
          TODO"
    ~spec:[]
    ~default:()
    begin fun buffer () ->
      run buffer (Query_protocol.Outline)
    end
  ;

  command "path-of-source"
    ~doc:"path-of-source -file a.mli -file a.ml\n\
          \tlooks for first file with a matching name in the project source \
          and build paths"
    ~spec: [
      ("-file",
       "<filename> filename to look for in project paths",
       Marg.param "filename" (fun file files -> file :: files)
      )
    ]
    ~default:[]

    begin fun buffer filenames ->
      run buffer (Query_protocol.Path_of_source (List.rev filenames))
    end
  ;

  command "refactor-open"
    ~doc:"search-by-polarity -position pos -action <qualify|unqualify>\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (action,_pos) -> (action,pos))
      );
      ("-action",
       "<qualify|unqualify> Direction of rewriting",
       Marg.param "<qualify|unqualify>" (fun action (_action,pos) ->
           match action with
           | "qualify" -> (Some `Qualify,pos)
           | "unqualify" -> (Some `Unqualify,pos)
           | _ -> failwith "invalid -action"
         )
      );
    ]
    ~default:(None,`None)
    begin fun buffer -> function
      | (None, _) -> failwith "-action is mandatory"
      | (_, `None) -> failwith "-position is mandatory"
      | (Some action, (#Msource.position as pos)) ->
        run buffer (Query_protocol.Refactor_open (action,pos))
    end
  ;

  command "search-by-polarity"
    ~doc:"search-by-polarity -position pos -query ident\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (query,_pos) -> (query,pos))
      );
      ("-query",
       "<string> Query of the form TODO",
       Marg.param "string" (fun query (_prefix,pos) -> (query,pos))
      );
    ]
    ~default:("",`None)
    begin fun buffer (query,pos) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Polarity_search (query,pos))
    end
  ;

  command "shape"
    ~doc:"shape -position pos\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos _pos -> pos)
      );
    ]
    ~default:`None
    begin fun buffer -> function
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Shape pos)
    end
  ;

  command "type-enclosing"
    ~doc:"type-enclosing -position pos [-expression expr -cursor n]\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (expr,cursor,_pos,index) -> (expr,cursor,pos,index))
      );
      ("-expression",
       "<string> Expression to type",
       Marg.param "string" (fun expr (_expr,cursor,pos,index) -> (expr,cursor,pos,index))
      );
      ("-cursor",
       "<int> Position of the cursor inside expression",
       Marg.param "int" (fun cursor (expr,_cursor,pos,index) ->
           match int_of_string cursor with
           | cursor -> (expr,cursor,pos,index)
           | exception exn ->
             failwith "cursor should be an integer"
         )
      );
      ("-index",
       "<int> Only print type of <index>'th result",
       Marg.param "int" (fun index (expr,cursor,pos,_index) ->
           match int_of_string index with
           | index -> (expr,cursor,pos,Some index)
           | exception exn ->
             failwith "index should be an integer"
         )
      );
    ]
    ~default:("",-1,`None,None)
    begin fun buffer (expr,cursor,pos,index) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        let expr =
          if expr = "" then None
          else
            let cursor = if cursor = -1 then String.length expr else cursor in
            Some (expr, cursor)
        in
        run buffer (Query_protocol.Type_enclosing (expr,pos,index))
    end
  ;

  command "type-expression"
    ~doc:"type-expression -position pos -expression expr\n\t\
          TODO"
    ~spec: [
      ("-position",
       "<position> Position to complete",
       marg_position (fun pos (expr,_pos) -> (expr,pos))
      );
      ("-expression",
       "<string> Expression to type",
       Marg.param "string" (fun expr (_expr,pos) -> (expr,pos))
      );
    ]
    ~default:("",`None)
    begin fun buffer (expr,pos) ->
      match pos with
      | `None -> failwith "-position <pos> is mandatory"
      | #Msource.position as pos ->
        run buffer (Query_protocol.Type_expr (expr,pos))
    end
  ;

  (* Implemented without support from Query_protocol.  This command might be
     refactored if it proves useful for old protocol too.  *)
  command "check-configuration"
    ~doc:"check-configuration\n\t\
          TODO"
    ~spec:[]
    ~default:()
    begin fun (trace, config, source) () ->
      let pipeline = Mpipeline.make trace config source in
      let config = Mpipeline.final_config pipeline in
      `Assoc [
        "dot_merlins", `List (List.rev_map Json.string
                                Mconfig.(config.merlin.dotmerlin_loaded));
        "failures", `List (List.map Json.string
                             Mconfig.(config.merlin.failures));
      ]
    end
  ;

]
