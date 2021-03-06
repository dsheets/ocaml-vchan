(*
 * Copyright (c) 2014 Citrix Systems Inc
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

let config_mk = "config.mk"

let verbose = ref false

(* Configure script *)
let find_ocamlfind name =
  let found =
    try
      let (_: string) = Findlib.package_property [] name "requires" in
      true
    with
    | Not_found ->
      (* property within the package could not be found *)
      true
    | Findlib.No_such_package(_,_ ) ->
      false in
  if !verbose then Printf.fprintf stderr "querying for ocamlfind package %s: %s" name (if found then "ok" else "missing");
  found

let output_file filename lines =
  let oc = open_out filename in
  let lines = List.map (fun line -> line ^ "\n") lines in
  List.iter (output_string oc) lines;
  close_out oc

let find_header name =
  let c_program = [
    Printf.sprintf "#include <%s>" name;
    "int main(int argc, const char *argv){";
    "return 0;";
    "}";
  ] in
  let c_file = Filename.temp_file "looking_for_header" ".c" in
  let o_file = c_file ^ ".o" in
  output_file c_file c_program;
  let found = Sys.command (Printf.sprintf "cc -c %s -o %s %s" c_file o_file (if !verbose then "" else "2>/dev/null")) = 0 in
  if Sys.file_exists c_file then Sys.remove c_file;
  if Sys.file_exists o_file then Sys.remove o_file;
  Printf.printf "Looking for %s: %s\n" name (if found then "ok" else "missing");
  found

module Common = struct
  type t = {
    build: string option;
    host: string option;
    target: string option;
    program_prefix: string option;
    prefix: string option;
    exec_prefix: string option;
    bindir: string option;
    sbindir: string option;
    sysconfdir: string option;
    datadir: string option;
    includedir: string option;
    libdir: string option;
    libexecdir: string option;
    localstatedir: string option;
    sharedstatedir: string option;
    mandir: string option;
    infodir: string option;
  }
  (** Default options provided by CentOS 6.5 %configure macro *)

  let make build host target program_prefix prefix exec_prefix bindir sbindir sysconfdir datadir includedir
    libdir libexecdir localstatedir sharedstatedir mandir infodir =
    { build; host; target; program_prefix; prefix; exec_prefix; bindir; sbindir; sysconfdir; datadir; includedir;
      libdir; libexecdir; localstatedir; sharedstatedir; mandir; infodir }

  let _common_options = "COMMON CONFIGURE OPTIONS"
  let help = [
   `S _common_options;
   `P "These options are common to all configure implementations.";
  ]

  let options_t =
    let open Cmdliner in
    let docs = _common_options in
    let o name = Arg.(value & opt (some string) None & info [name] ~docs ~doc:("Set the standard configure option " ^ name)) in
    Term.(pure make $ (o "build") $ (o "host") $ (o "target") $ (o "program-prefix") $ (o "prefix")
                    $ (o "exec-prefix") $ (o "bindir") $ (o "sbindir") $ (o "sysconfdir") $ (o "datadir")
                    $ (o "includedir") $ (o "libdir") $ (o "libexecdir") $ (o "localstatedir")
                    $ (o "sharedstatedir") $ (o "mandir") $ (o "infodir"))
end

type opt = {
  name: string;
  deps_satisfied: unit -> bool;
}

let configure options common v overrides =
  verbose := v;
  let failed = ref false in
  let lines =
    List.fold_left (fun acc (opt, override) ->
      match opt.deps_satisfied (), override with
      | false, Some true ->
        Printf.fprintf stderr "Error: %s has unsatisfied dependencies but has been requested via the command-line" opt.name;
        failed := true;
        acc
      | true, (Some true | None) ->
        Printf.sprintf "ENABLE_%s=--enable-%s" (String.uppercase opt.name) opt.name :: acc
      | true, Some false
      | false, (Some false | None) ->
        Printf.sprintf "ENABLE_%s=--disable-%s" (String.uppercase opt.name) opt.name :: acc
     ) [] (List.combine options overrides) in
  if !failed then exit 1;
  let lines =
    [ "# Warning - this file is autogenerated by the configure script";
      "# Do not edit" ] @ lines in
  output_file config_mk lines

let xenctrl = {
  name = "xenctrl";
  deps_satisfied = (fun () -> find_header "xenctrl.h" && (find_ocamlfind "xen-evtchn"));
}

let xen = {
  name = "xen";
  deps_satisfied = (fun () -> find_ocamlfind "mirage-xen");
}

let options = [ xenctrl; xen ]

open Cmdliner

let configure_t =
  let arg = Arg.(value & flag & info ["verbose"; "v"] ~doc:"enable verbose printing") in
  let to_term x =
    Arg.(value & opt (some bool) None & info [x.name] ~doc:("Forcibly enable or disable option '" ^ x.name ^ "'")) in
  let open Term in
  let cons x y = x :: y in
  let overrides = List.fold_left (fun t opt -> pure cons $ opt $ t) (pure []) (List.rev (List.map to_term options)) in

  pure configure $ (pure options) $ Common.options_t $ arg $ overrides

let () = 
  let info = Term.info "configure" ~version:"0.1" ~doc:"Configures this package" in
  match Term.eval (configure_t, info) with
  | `Error _ -> exit 1 
  | _ -> exit 0
