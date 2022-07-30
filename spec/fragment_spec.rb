
class Qrpm::Fragment::Fragment
  # Flattens fragment tree into a list
  def flatten() ([self] + fragments).flatten end

  # Flattens fragment tree into a list of leaf nodes
  def leaf() (fragments.empty? ? [self] : fragments.map(&:leaf)).flatten end
end

describe "Qrpm" do
  describe "Fragment" do
    def parse(s) Qrpm::Fragment::Fragment.parse(s) end
    def leaf(s) parse(s).leaf end

    describe ".parse" do
      it "returns an Expression object" do
        expect(Qrpm::Fragment::Fragment.parse("Hello world")).to be_a Qrpm::Fragment::Expression
      end

      it "splits string into fragments" do
        expect(leaf("Hello $var world").map(&:source)).to eq ["Hello ", "$var", " world"]
      end

      it "parses $NAME variables" do
        var = leaf("$var").first
        expect(var).to be_a Qrpm::Fragment::VariableFragment
        expect(var.source).to eq "$var"
        expect(var.name).to eq "var"
      end
      it "parses ${NAME} variables" do
        var = leaf("${var}").first
        expect(var).to be_a Qrpm::Fragment::VariableFragment
        expect(var.source).to eq "${var}"
        expect(var.name).to eq "var"
      end
      it "parses $(CMD) shell commands" do
        cmd = parse("$(cmd arg arg)").fragments.first
        expect(cmd).to be_a Qrpm::Fragment::CommandFragment
        expect(cmd.source).to eq "$(cmd arg arg)"
        expect(cmd.command).to eq "cmd arg arg"
        expect(cmd.fragments.size).to eq 1
        expect(cmd.fragments.first.class).to eq Qrpm::Fragment::TextFragment
      end

      context "in shell expansions" do
        it "parses ${{NAME}} variables" do
          obj = leaf("$(cmd ${{var}} arg)").first
          prefix, var, suffix = leaf("$(cmd ${{var}} arg)")
          expect(prefix.source).to eq "cmd "
          expect(var).to be_a Qrpm::Fragment::CommandVariableFragment
          expect(var.source).to eq "${{var}}"
          expect(var.name).to eq "var"
          expect(suffix.source).to eq " arg"
        end
      end

      it "handles '\\' escapes"
    end

    describe "#variables" do
      it "returns a list of variables in the fragment and its descendants" do
        e = parse("Hello $a world")
        expect(e.variables).to eq %w(a)
        e = parse("Hello $a $(echo ${{b}})")
        expect(e.variables).to eq %w(a b)
      end
    end

    describe "#interpolate" do
      def dict() { "a" => "word" } end
      it "replaces $NAME variables" do
        e = parse("Hello $a world")
        expect(e.interpolate(dict)).to eq "Hello word world"
      end
      it "replaces ${NAME} variables" do
        e = parse("Hello ${a} world")
        expect(e.interpolate(dict)).to eq "Hello word world"
      end
      it "replaces $(CMD) shell commands" do
        e = parse("Hello $(echo word) world")
        expect(e.interpolate(dict)).to eq "Hello word world"
      end
      context "in shell commands" do
        it "replaces ${{NAME}} variables" do
          e = parse("Hello $(echo ${{a}}) world")
          expect(e.interpolate(dict)).to eq "Hello word world"
        end
      end
    end
  end
end
