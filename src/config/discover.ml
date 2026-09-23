(* Portable build-time configuration for ocaml-highs.
 *
 * HiGHS ships a pkg-config file (highs.pc), so we lean on that instead of
 * hand-rolled path detection. Runs on every platform where OCaml runs.
 *
 * Emits into ../ :
 *   c_flags.sexp          -I include dirs
 *   c_library_flags.sexp  -L lib dirs + -lhighs + rpath
 *
 * If HIGHS_CFLAGS or HIGHS_LIBS are set in the environment, they override
 * pkg-config's output. This is how CI or a custom build can point the
 * binding at a specific HiGHS install.
 *)

module C = Configurator.V1

let getenv k = try Some (Sys.getenv k) with Not_found -> None

let write_file file contents =
  let oc = open_out file in
  output_string oc contents;
  close_out oc

let sexp_list items = "(" ^ String.concat " " items ^ ")\n"

(* Add an rpath for each -L flag so we don't need DYLD_LIBRARY_PATH at
 * runtime on macOS or LD_LIBRARY_PATH on Linux. *)
let rpath_flags c libs =
  let sep = match C.ocaml_config_var c "system" with
    | Some "macosx" -> Some ","
    | Some s when String.length s >= 5 && String.sub s 0 5 = "linux" -> Some "="
    | _ -> None
  in
  match sep with
  | None -> []
  | Some sep ->
    libs
    |> List.filter_map (fun s ->
         if String.length s > 2 && String.sub s 0 2 = "-L"
         then Some ("-Wl,-rpath" ^ sep ^ String.sub s 2 (String.length s - 2))
         else None)

let split_ws s =
  String.split_on_char ' ' s |> List.filter (fun s -> s <> "")

let () =
  C.main ~name:"ocaml-highs-discover" (fun c ->
    let cflags, libs =
      match getenv "HIGHS_CFLAGS", getenv "HIGHS_LIBS" with
      | Some cf, Some lb -> split_ws cf, split_ws lb
      | _ ->
        (match C.Pkg_config.get c with
         | None ->
           prerr_endline "ERROR: pkg-config not found on PATH.";
           prerr_endline "  Install HiGHS (with pkgconfig): brew install highs";
           prerr_endline "  or set HIGHS_CFLAGS and HIGHS_LIBS in the environment.";
           exit 1
         | Some pc ->
           match C.Pkg_config.query pc ~package:"highs" with
           | Some { cflags; libs } -> cflags, libs
           | None ->
             prerr_endline "ERROR: pkg-config could not find 'highs'.";
             prerr_endline "  Install HiGHS: brew install highs (macOS)";
             prerr_endline "  or set HIGHS_CFLAGS and HIGHS_LIBS to override.";
             exit 1)
    in
    let rpaths = rpath_flags c libs in
    write_file "c_flags.sexp"         (sexp_list cflags);
    write_file "c_library_flags.sexp" (sexp_list (libs @ rpaths));
    prerr_endline
      (Printf.sprintf "configure: highs cflags=%s libs=%s"
         (String.concat " " cflags) (String.concat " " libs)))
