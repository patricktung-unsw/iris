# The form test helper renders, checks and fills a form as the pinned fork
# commit does (form_helper.rb's header names it), on small forms written
# to a temporary folder. Needs only Ruby, so bin/check runs it:
#
#   ruby lib/tests/test_form_helper.rb

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "form_helper"

class FormHelperTest < Minitest::Test
  def setup
    @apps = Dir.mktmpdir("iris-form-helper-test-")
  end

  def teardown
    FileUtils.rm_rf(@apps)
  end

  # Writes `text` as workflows/<name>/form.yml.erb and renders it.
  def form(text, name = "fixture")
    path = File.join(@apps, name, "form.yml.erb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    FormHelper.render(path)
  end

  def script(f, given = {})
    FormHelper.script(f, FormHelper.defaults(f, given))
  end

  # A form rendered for another clone, such as the system clone a new
  # workflow isn't in yet, reads its own files from its own folder, so
  # the render is this commit as that clone would serve it (#145).
  def test_a_render_for_another_clone_reads_the_forms_own_files
    path = File.join(@apps, "fixture", "form.yml.erb")
    FileUtils.mkdir_p(File.join(@apps, "fixture", "src"))
    File.write(File.join(@apps, "fixture", "src", "entry.txt"), "own entry")
    File.write(path, <<~YAML)
      <%- code = File.expand_path(File.join(@apps_dir, @OC_DIR_NAME)) -%>
      form: {}
      script: "CODE=<%= code %> <%= File.read(File.join(code, "src", "entry.txt")) %>"
    YAML
    other = File.join(@apps, "elsewhere", "workflows")
    assert_equal "CODE=#{other}/fixture own entry", FormHelper.render(path, other)["script"]
    assert_equal "CODE=#{@apps}/fixture own entry", FormHelper.render(path)["script"]
    assert_raises(Errno::ENOENT) { File.read(File.join(other, "fixture", "src", "entry.txt")) }
  end

  def test_halt_in_check_rejects_with_its_message
    f = form(<<~YAML)
      form:
        hours:
          widget: number
          value: 0
      script: "echo"
      check: |
        halt 500, "Walltime cannot be zero." if @hours.to_i == 0
    YAML
    assert_equal "Walltime cannot be zero.", FormHelper.check(f, FormHelper.defaults(f))
    assert_nil FormHelper.check(f, FormHelper.defaults(f, hours: 2))
  end

  # run.rb rescues every exception from check: and shows its message.
  def test_any_error_in_check_rejects_with_its_message
    f = form(<<~YAML)
      form:
        mem:
          widget: text
          value: "lots"
      script: "echo"
      check: |
        Integer(@mem)
    YAML
    assert_match(/invalid value for Integer\(\): "lots"/, FormHelper.check(f, FormHelper.defaults(f)))
  end

  # lib/form.rb splits the script on newlines, dropping trailing empty
  # lines, and the pane joins its lines with newlines, so the submitted
  # script ends with its last line's text and no newline.
  def test_the_script_ends_without_a_newline_as_submitted
    f = form(<<~YAML)
      form: {}
      script: |+
        echo one

        echo two


    YAML
    assert_equal "echo one\n\necho two", script(f)
  end

  MAIL = <<~YAML
    form:
      mail_events:
        widget: checkbox
        separator: ""
        options:
          - [ "On abort", "a" ]
          - [ "On end",   "e" ]
    script: |
      #PBS -m \#{mail_events}
      --field "mail_events=\#{:mail_events}"
      done
  YAML

  def test_a_checked_checkbox_fills_both_forms_of_its_field
    assert_equal %(#PBS -m ae\n--field "mail_events=ae"\ndone), script(form(MAIL), mail_events: "ae")
  end

  # ocForm.showLine empties a checkbox's line when nothing is checked,
  # however the line names it.
  def test_an_unchecked_checkbox_drops_every_line_holding_it
    assert_equal "done", script(form(MAIL))
  end

  # With no separator, ocForm.showLine writes the line once per value.
  def test_a_checkbox_with_no_separator_repeats_its_line_per_checked_option
    f = form(<<~YAML)
      form:
        steps:
          widget: checkbox
          value: [ "Train", "Segment" ]
          options:
            - [ "Train",   "train"   ]
            - [ "Score",   "score"   ]
            - [ "Segment", "segment" ]
      script: |
        run \#{steps}
    YAML
    assert_equal "run train\nrun segment", script(f)
  end

  # run.rb's set_check_value: one checked value is itself, several an array.
  def test_check_sees_a_checkbox_with_no_separator_as_run_rb_sets_it
    f = form(<<~YAML)
      form:
        steps:
          widget: checkbox
          options:
            - [ "Train", "train" ]
            - [ "Score", "score" ]
      script: "echo"
      check: |
        oc_assert(false, @steps.inspect)
    YAML
    assert_equal "nil", FormHelper.check(f, FormHelper.defaults(f))
    assert_equal '"train"', FormHelper.check(f, FormHelper.defaults(f, steps: ["train"]))
    assert_equal '["train", "score"]', FormHelper.check(f, FormHelper.defaults(f, steps: %w[train score]))
  end

  MODULES = <<~YAML
    form:
      module:
        widget: multi_select
        separator: " "
        value: [ "GCC 14", "julia/1.11" ]
        options:
          - [ "GCC 14", "gcc/14.2.0" ]
          - [ "R 4.4",  "R/4.4.1"    ]
    script: |
      module load \#{module}
    check: |
      oc_assert(false, @module)
  YAML

  # The fork, unlike 1.9.0, keeps an entry that is no option as typed:
  # form.js's getValue falls back to its text, run.rb's check to its value.
  def test_a_multi_select_fills_its_options_values_and_typed_entries
    f = form(MODULES)
    assert_equal "module load gcc/14.2.0 julia/1.11", script(f)
    assert_equal "gcc/14.2.0 julia/1.11", FormHelper.check(f, FormHelper.defaults(f))
  end

  MAIL_SELECT = <<~YAML
    form:
      mail_events:
        widget: select
        value: "On abort or end"
        options:
          - [ "On abort",        "a"  ]
          - [ "On abort or end", "ae" ]
          - [ "Never",           "n"  ]
    script: |
      #PBS -m \#{mail_events}
      --field "mail_events=\#{:mail_events}"
  YAML

  # lib/form.rb selects the option whose label is the field's value, and
  # form.js's getValue fills the selected option's data value.
  def test_a_select_fills_the_data_value_of_the_option_its_value_labels
    assert_equal %(#PBS -m ae\n--field "mail_events=ae"), script(form(MAIL_SELECT))
  end

  # A value naming no label selects no option, so the browser shows the
  # first.
  def test_a_select_whose_value_labels_no_option_fills_the_first
    f = form(MAIL_SELECT.sub('value: "On abort or end"', 'value: "ae"'))
    assert_equal %(#PBS -m a\n--field "mail_events=a"), script(f)
  end
end
