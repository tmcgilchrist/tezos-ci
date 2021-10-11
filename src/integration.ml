let template ~script =
  let build = Build.v in
  let from =
    Variables.image_template__runtime_build_test_dependencies_template
  in
  Obuilder_spec.(
    stage ~from ~child_builds:[ ("build", build) ]
      [
        user ~uid:100 ~gid:100;
        workdir "/home/tezos";
        copy [ "tests_python" ] ~dst:"./tests_python";
        copy [ "poetry.lock"; "pyproject.toml" ] ~dst:".";
        copy [ "scripts/version.sh" ] ~dst:"scripts/version.sh";
        copy ~from:(`Build "build") [ "/" ] ~dst:".";
        run "find . -maxdepth 3";
        run ". ./scripts/version.sh";
        run ". /home/tezos/.venv/bin/activate";
        run "mkdir tests_python/tmp";
        run "touch tests_python/tmp/empty__to_avoid_glob_failing";
        workdir "tests_python";
        run "%s" script;
      ])

let slow_test ~protocol_id test_name =
  let script =
    Fmt.str
      {| poetry run pytest "tests_%s/test_%s.py" --exitfirst -m "slow" -s --log-dir=tmp "--junitxml=reports/%s_%s.xml" 2>&1 | tee "tmp/%s_%s.out" | tail |}
      protocol_id test_name protocol_id test_name protocol_id test_name
  in
  template ~script

let fast_test ~protocol_id =
  let script =
    Fmt.str
      {| poetry run pytest "tests_%s/" --exitfirst -m "not slow" -s --log-dir=tmp "--junitxml=reports/%s_batch.xml" 2>&1 | tee "tmp/%s_batch.out" | tail |}
      protocol_id protocol_id protocol_id
  in
  template ~script

let examples =
  let script =
    {|PYTHONPATH=\$PYTHONPATH:./ poetry run python examples/forge_transfer.py &&
    PYTHONPATH=\$PYTHONPATH:./ poetry run python examples/example.py && 
    PYTHONPATH=./ poetry run pytest --exitfirst examples/test_example.py |}
  in
  template ~script

let job ~build (protocol : Tezos_repository.Active_protocol.t Current.t) =
  let open Current.Syntax in
  let slow_tests =
    let+ protocol = protocol in
    protocol.slow_tests
  in

  let slow_tests =
    Current.list_iter ~collapse_key:"slow-test"
      (module struct
        type t = string

        let pp = Fmt.string

        let compare = String.compare
      end)
      (fun name ->
        let spec =
          let+ name = name and+ protocol = protocol in
          slow_test ~protocol_id:protocol.id name
        in
        let* protocol = protocol and* name = name in
        build ~label:("integration:test_" ^ protocol.id ^ "_" ^ name) spec)
      slow_tests
  in
  let batch_test =
    let+ protocol = protocol in
    fast_test ~protocol_id:protocol.id
  in
  Current.all
    [
      slow_tests;
      (let* protocol = protocol in
       build ~label:(protocol.id ^ "_batch") batch_test);
    ]

let job ~build (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let active_protocols =
    let+ analysis = analysis in
    analysis.active_protocols
  in
  let protocol_tests =
    Current.list_iter ~collapse_key:"active-protocols"
      (module Tezos_repository.Active_protocol)
      (job ~build) active_protocols
  in
  let examples =
    build ~label:"integration:examples" (Current.return examples)
  in
  Current.all [ protocol_tests; examples ]
