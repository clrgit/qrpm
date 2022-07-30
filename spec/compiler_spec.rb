
describe "Qrpm" do
  describe "Compiler" do
    describe "#parse" do
      def parse(h) Qrpm::Compiler.new({}, system_dirs: false, defaults: false, srcdir: false).parse(h) end

      it "parses an empty value" do
        r = parse({})
        expect(r.signature).to eq "RootNode()"
      end
      it "parses Integer values" do
        r = parse a: 42
        expect(r.signature).to eq "RootNode(ValueNode(a,42))"
      end
      it "parses Float values" do
        r = parse a: 42.1
        expect(r.signature).to eq "RootNode(ValueNode(a,42.1))"
      end
      it "parses String values" do
        r = parse a: "Hello"
        expect(r.signature).to eq "RootNode(ValueNode(a,Hello))"
      end
      it "parses Hash values" do
        r = parse a: { b: "Hello" }
        expect(r.signature).to eq "RootNode(HashNode(a,ValueNode(b,Hello)))"
      end
      it "parses Array values" do
        r = parse a: { b: %w(file1 file2) } # Nested because top-level arrays are directories
        expect(r.signature).to eq "RootNode(HashNode(a,ArrayNode(b,ValueNode(0,file1),ValueNode(1,file2))))"
      end
      it "parses Directory values" do
        r = parse a: %w(file1 file2) # Nested because top-level arrays are directories
        expect(r.signature).to eq "RootNode(DirectoryNode(a,FileNode(0,file1),FileNode(1,file2)))"
      end
      it "parses nil values" do
        r = parse a: nil
        expect(r.signature).to eq "RootNode(ValueNode(a,))"
      end
    end

    describe "#analyze" do
      def options = { 
        check_undefined: false, 
        check_mandatory: false, 
        check_field_types: false, 
        check_directory_types: false 
      } 

      def analyze(h) check(h, **options) end

      def check(h, **opts)
        opts = options.merge(opts)
        c = Qrpm::Compiler.new({}, system_dirs: false, defaults: false, srcdir: false)
        c.parse(h)
        c.analyze(**opts)
        c
      end

      def check_undefined(h) check(h, check_undefined: true) end
      def check_mandatory(h) check(h, check_mandatory: true) end
      def check_field_types(h) check(h, check_field_types: true) end

      describe "initializes #deps" do
        it "registers nodes by path" do
          c = analyze "a" => { "b" => "$c" }
          expect(c.deps).to eq "a.b" => %w(c)
        end
        it "definitions without references have [] as value" do
          c = analyze "a" => "b"
          expect(c.deps).to eq "a" => []
        end
        it "registers references in directory keys" do
          c = analyze "$a$b" => ["d"]
          expect(c.deps).to eq "$a$b" => %w(a b)
        end
        it "registers references in values" do
          c = analyze "a" => "$b"
          expect(c.deps).to eq "a" => %w(b)
        end
        it "ignores references in keys" do
          c = analyze "a" => { "$b" => { "c" => "$d" } }
          expect(c.deps).to eq "a.$b.c" => %w(d)
        end
        it "removes duplicate dependencies" do
          c = analyze "a" => "$b$b"
          expect(c.deps).to eq "a" => %w(b)
        end
      end

      describe "initializes #defs" do
        it "registers ValueNodes by path" do
          c = analyze "a" => "b", "c" => { "d" => "e" }
          expect(c.defs.keys).to eq %w(a c.d)
          expect(c.defs.values.all? { |v| v.is_a?(Qrpm::ValueNode) }).to eq true
        end
      end

      describe "checks for" do
        it "undefined variables" do
          expect { check_undefined "a" => "$b" }.to raise_error ::Qrpm::CompileError
          expect { check_undefined "a" => "$b", "b" => "value" }.not_to raise_error
        end
        it "references to hashes" do
          expect { check_undefined "a" => { "b" => "c" }, "d" => "$a" }.to raise_error ::Qrpm::CompileError
          expect { check_undefined "a" => { "b" => "c" }, "d" => "$a.b" }.not_to raise_error
        end
        it "references to arrays" do
          expect { check_undefined "a" => ["1", "2", "3"], "d" => "$a" }.to raise_error ::Qrpm::CompileError
        end
        it "missing mandatory variables - there are none!" do
          expect { check_mandatory "a" => "value" }.to raise_error ::Qrpm::CompileError
          expect { 
            check_mandatory "name" => "App", "summary" => "An App", "version" => "1.2.3" 
          }.not_to raise_error
        end
        it "types of built-in variables" do
          expect { check_field_types "name" => { "b" => "c" } }.to raise_error ::Qrpm::CompileError
          expect { check_field_types "name" => "value" }.not_to raise_error
        end
        it "types of directories" do
        end
      end
    end
  end
end

__END__

describe "Qrpm::Compiler" do
# def parse(conf) Qrpm::Compiler.new(system_dirs: false).parse(conf) end
# def analyze(conf) parse(conf).analyze end
# def compile(conf) Qrpm::Compiler.new(system_dirs: false).compile(conf) end
#
# describe "#initialize" do
#   context "when :system_dirs is" do
#     it "true: it includes the system directories" do
#       c = Qrpm::Compiler.new(system_dirs: true)
#       expect(c.defs).to eq Qrpm::SYSTEM_DIRS
#     end
#     it "false: it doesn't include the system directories" do
#       c = Qrpm::Compiler.new(system_dirs: false)
#       expect(c.defs).to be_empty
#     end
#   end
# end

  describe "#parse" do
    def s1() { "$v1" => "$v2" } end
    def s2() { "$v1" => "$v2.$v3", "$v2" => { "$v3" => "value" } } end

    it "collects definitions" do
      expect(parse(s2).defs).to eq "$v1" => "$v2.$v3", "$v2.$v3" => "value"
    end

    it "collects key expressions" do 
      v = parse(s1).keys
      expect(v.keys).to eq ["$v1"]
      expect(v.values.map(&:to_s)).to eq ["Expression('$v1'){VarFragment(v1)}"]

      v = parse(s2).keys
      expect(v.keys).to eq ["$v1", "$v2", "$v2.$v3"] # FIXME Should $v2 be included?
      expect(v.values.map(&:to_s)).to eq [
          "Expression('$v1'){VarFragment(v1)}", 
          "Expression('$v2'){VarFragment(v2)}", 
          "Expression('$v3'){VarFragment(v3)}"
      ]
    end

    it "collects value expressions" do
      v = parse(s1).values
      expect(v.keys).to eq ["$v1"]
      expect(v.values.map(&:to_s)).to eq ["Expression('$v2'){VarFragment(v2)}"]

      v = parse(s2).values
      expect(v.keys).to eq ["$v1", "$v2.$v3"] # FIXME $v2 is not included here
      expect(v.values.map(&:to_s)).to eq [
        "Expression('$v2.$v3'){VarFragment(v2), VarFragment(v3)}", 
        "Expression('value'){TextFragment('value')}"
      ]
    end

    it "collects dependencies" do
      v = parse(s1).deps
      expect(v).to eq "$v1"=>["v2"], nil=>["v2"] # FIXME nil? Seems like a bug
      v = parse(s2).deps
      expect(v).to eq "$v1"=>["v2", "v3"], "$v2.$v3"=>[], "$v2"=>[], nil=>["v2", "v3"]
    end

    it "partitions definitions into QRPM variables and directories" do
      v = parse({
        "name" => "$value",
        "$var" => "$value",
        "/dir" => "$value"
      })
      expect(v.vars).to eq "name" => "$value"
      expect(v.dirs).to eq "$var" => "$value", "/dir" => "$value"
    end
  end

  describe "#analyze" do
    it "adds empty depencies to #deps"
    it "removes duplicate dependencies"
    it "detects undefined variables"
  end


  describe "something" do
    it "does something" do
      conf = {
        k1: "$v1",
        k2: {
          "$k21" => "$v2" # Oops
        }
      }
      compiler = parse(conf)
      expect(compiler.defs).to eq "k1"=>"$v1", "k2.$k21"=>"$v2"
      expect(compiler.deps).to eq "k1"=>["v1"], "k2.$k21"=>["v2"], "k2"=>["v2"], nil=>["v1", "v2"] # FIXME nil?
#
#
#     expect(qrpm).to be_a Qrpm::Qrpm
#
#     expect(qrpm.defs).to eq "k1" => "$val1", "k2.k21" => "$val21", "k2.k22" => "$val22 ${k2.k21}" 
#     expect(qrpm.deps).to eq "k1" => %w(val1), "k2.k21" => %w(val21), "k2.k22" => %w(val22 k2.k21)
    end
#   it "inherits key dependencies" do
#     h = {
#       k1: "$val1",
#       "$k2/dir" => {
#         k21: "$k1",
#       }
#     }
#     parser.collect_variables(h)
#     expect(parser.deps).to eq "k1" => %w(val1), "$k2/dir.k21" => %w(k2 k1)
#   end
  end
end
