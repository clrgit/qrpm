
class Qrpm::Node
  public_method :ref
end

describe "Qrpm" do
# include Qrpm

  let(:root) { Qrpm::RootNode.new }
  def fragment(s) Qrpm::Fragment::Fragment.parse s end
  def value(parent, name, expr = "expr") Qrpm::ValueNode.new parent, name, fragment(expr) end
  def file(parent, expr = "file") Qrpm::FileNode.make(parent, expr) end
  def hash(parent, name) Qrpm::HashNode.new(parent, name) end
  def array(parent, name) Qrpm::ArrayNode.new(parent, name) end
  def dir(parent, name) Qrpm::DirectoryNode.new(parent, fragment(name)) end

  describe "Node" do
    describe "#initialize" do
      it "doesn't link up the root node" do
        expect(root.parent).to eq nil
        expect(root.path).to eq nil
      end

      it "links up with parent" do
        v = value(root, "a")
        expect(v.parent).to be root
      end

      it "computes #path" do
        h = hash(root, "h")
        kv = value(h, "k")
        a = array(root, "a")
        ae = value(a, 0)
        d = dir(root, "d")

        expect(root.path).to eq nil
        expect(h.path).to eq "h"
        expect(kv.path).to eq "h.k"
        expect(a.path).to eq "a"
        expect(ae.path).to eq "a[0]"
        expect(d.path).to eq "d"
      end


      it "sets the interpolated flag to false" do
        expect(value(root, "v").interpolated?).to eq false
      end
    end

    describe "#interpolate" do
      it "sets the interpolated? flag" do
        v = value(root, "a")
        v.interpolate({})
        expect(v.interpolated?).to eq true
      end

      it "interpolates values" do
        v = value(root, "a", "$b")
        v.interpolate("b" => "B")
        expect(v.value).to eq "B"
      end

      context "when interpolates hashes" do
        it "doesn't cascade to its members"
      end

      context "when interpolates arrays" do
        it "cascades to its elements"
      end

      context "when interpolating directories" do
        it "interpolates the key too" do
          d = dir(root, "$d")
          f = file(d, "f")
          d.interpolate("d" => "D")
          expect(d.key).to eq "D"
        end
      end
    end

    describe ".ref" do
      def ref(*args) Qrpm::Node.ref(*args) end

      it "returns the element is parent is nil" do
        expect(ref(nil, "name")).to eq "name"
      end
      it "adds a .<name> to parent_ref if the element is a string" do
        expect(ref("ref", "name")).to eq "ref.name"
      end
      it "adds a [<name>] to parent_ref if the element is an integer" do
        expect(ref("ref", 42)).to eq "ref[42]"
      end
    end
  end

  describe "ValueNode" do
    def v(expr = "expr") value(root, "v", expr) end

    describe "#source" do
      it "returns the source of the expression" do
        expect(v.source).to eq "expr"
      end
    end

    describe "#value" do
      it "is nil initially" do
        expect(v.value).to eq nil
      end
      it "is initialized by #interpolate" do
        expect(v.interpolate({}).value).to eq "expr"
      end
    end

    describe "#variables" do
      it "returns a list of variables in #expr" do
        expect(value(root, "$a", "$b").variables).to eq %w(b)
      end
    end

    describe "#interpolate" do
      def interpolate() 
        value(root, "$key", "$value").interpolate "key" => "KEY", "value" => "VALUE"
      end

      it "doesn't interpolate variables in #name" do
        expect(interpolate.key).to eq "$key"
      end
      it "interpolates variables in #expr" do
        expect(interpolate.value).to eq "VALUE"
      end
    end
  end
  
  describe "HashNode" do
    describe "#exprs" do
      it "returns the hash values" do
        h = hash(root, "h")
        kv1 = value(h, "k1", "v1")
        kv2 = value(h, "k2", "v2")
        expect(h.exprs).to eq [kv1, kv2]
      end
    end

    describe "#variables" do
      it "returns variables in the hash values" do
        h = hash(root, "h")
        kv1 = value(h, "k1", "$v1")
        kv2 = value(h, "k2", "$v2")
        expect(h.variables).to eq %w(v1 v2)
      end
    end

    describe "#interpolate" do
      it "does nothing" do
        true
      end
    end
  end

  describe "RootNode" do
    describe "#interpolate" do
      def d() @d ||= dir(root, "$dir") end
      def r() root.interpolate("dir" => "DIR") end
        
      it "interpolates DirectoryNode children" do
        d = dir(root, "$dir")
        root.interpolate("dir" => "DIR")
        expect(d.key).to eq "DIR"
      end
      it "doesn't interpolate other children" do
        v = value(root, "v", "$expr")
        root.interpolate("expr" => "EXPR")
        expect(v.interpolated?).to eq false
      end
    end
  end

  describe "FileNode" do
    def make(direxpr, filearg)
      file(dir(root, direxpr), filearg)
    end

    describe "::make(directory, name: String)" do
      it "creates a FileNode object with the given name" do
        f = make("dir", "file")
        expect(f).to be_a Qrpm::FileNode
        expect(f.expr["file"].source).to eq "file"
      end
    end
    describe "::make(directory, attributes: Hash)" do
      it "creates a FileNode object with the given attributes" do
        attrs = { name: "n", file: "f", perm: "0600" }
        f = make("dir", attrs)
        expect(f.expr.keys).to eq attrs.keys.map(&:to_s)
        expect(f.expr.values.map(&:source)).to eq attrs.values
      end
    end
    describe "#interpolate" do
      def node(filearg = "source/$file") 
        f = make("target/$dir", filearg)
        # interpolate through DirectoryNode, otherwise things becomes strange
        f.parent.interpolate("dir" => "DIR", "file" => "FILE", "link" => "LINK", "perm" => "PERM")
        f
      end

      it "sets #key to #name (it's an integer)" do
        expect(node.key).to eq 0
      end
      it "interpolates its attributes" do
        expect(node.value.values).to all be_interpolated
      end
      it "sets #srcpath to the interpolated value of file" do
        expect(node.srcpath).to eq "source/FILE"
      end
      it "sets #dstpath" do
        expect(node.dstpath).to eq "target/DIR/FILE"
      end
      it "sets #dstname to the basename of the source path" do
        expect(node.dstname).to eq "FILE"
      end
      it "sets reflink" do
        expect(node.reflink).to eq nil
        f = node(reflink: "src$link")
        expect(f.reflink).to eq "srcLINK"
      end
      it "sets symlink" do
        expect(node.symlink).to eq nil
        f = node(symlink: "src$link")
        expect(f.symlink).to eq "srcLINK"
      end
      it "sets perm" do
        expect(node.perm).to eq nil
        f = node(file: "$file", perm: "$perm") # "file" is required
        expect(f.perm).to eq "PERM"
      end
    end
  end

  describe "ArrayNode" do
    attr_reader :e1
    attr_reader :e2
    def a()
      @a ||= begin
        a = array(root, "a")
        @e1 = value(a, 0, "$e1")
        @e2 = value(a, 1, "$e2")
        a
      end
    end

    describe "#exprs" do
      it "returns the array elements" do
        expect(a.exprs).to eq [e1, e2]
      end
    end

    describe "#variables" do
      it "returns the variables in the array elements" do
        expect(a.variables).to eq %w(e1 e2)
      end
    end

    describe "#interpolate" do
      it "interpolates the array elements" do
        expect(a.exprs.map(&:interpolated?)).to all(be false)
        a.interpolate("e1" => "E1", "e2" => "E2")
        expect(a.exprs.map(&:interpolated?)).to all(be true)
      end
    end
  end

  describe "DirectoryNode" do
    describe "interpolate" do
      it "interpolates the key" do
        d = dir(root, "$dir").interpolate("dir" => "DIR")
        expect(d.key).to eq "DIR"
      end
      it "interpolates the file elements" do
        d = dir(root, "d")
        f = file(d, "$file")
        d.interpolate("file" => "FILE")
        expect(f.dstname).to eq "FILE"
      end
    end
  end
end


__END__


    def node1()
      Qrpm::ValueNode.new(Qrpm::RootNode.new, "key", "value")
    end

    def node2()
      r = Qrpm::RootNode.new
      h = Qrpm::HashNode.new(r, "hash_key")
      n = Qrpm::ValueNode.new(h, "value_key", "value")
    end

    def node3()
      r = Qrpm::RootNode.new
      h = Qrpm::HashNode.new(r, "hash")
      hn = Qrpm::ValueNode.new(h, "hash_key", "hash_value")
      a = Qrpm::ArrayNode.new(r, "array")
      an = Qrpm::ValueNode.new(a, 0, "array_value")
      r
    end

    it "#path is the concatenation of #parent.path and #key" do
      expect(node1.path).to eq "key"  
      expect(node2.path).to eq "hash_key.value_key"
    end

    describe "#dot" do
      it "evaluates member references" do
        r = node3
        expect(r.dot("hash.hash_key").value_source).to eq "hash_value"
      end
      it "evaluates array indexes" do
        r = node3
        expect(r.dot("array[0]").value_source).to eq "array_value"
      end
    end
  end

  describe "ValueNode" do
  end

  describe "HashNode" do
  end

  describe "ArrayNode" do
  end

  describe "RootNode" do
    def node() Qrpm::RootNode.new end
    it "#parent is nil" do
      expect(node.parent).to eq nil
    end
    it "#key is nil" do
      expect(node.key).to eq nil
    end
    it "#path is nil" do
      expect(node.path).to eq nil
    end
  end
end
