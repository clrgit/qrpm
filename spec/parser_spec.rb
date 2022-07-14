
class Qrpm::Parser
  public :collect_variables
end

describe "Qrpm::Parser" do
  def parse(conf) Qrpm::Parser.new(system_dirs: false).parse(conf) end
  def analyze(conf) parse(conf).analyze end
  def compile(conf) Qrpm::Parser.new(system_dirs: false).compile(conf) end

  describe "#initialize" do
    context "when :system_dirs is" do
      it "true: it includes the system directories"
      it "false: it doesn't include the system directories"
    end
  end

  describe "#parse" do
    it "collects definitions"
    it "collects key expressions"
    it "collects value expressions"
    it "collects dependencies"
    it "collects QRPM variables"
    it "collects directories"
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
