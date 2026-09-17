require 'yaml'

describe "template.yml" do
  let(:source) { File.read(Qrpm::QRPM_CONFIG_FILE_TEMPLATE) }
  let(:yaml) { YAML.load(source.sub(/^__END__\n.*/m, "")) || {} }

  it "only uses known fields" do
    expect(yaml.keys - Qrpm::FIELDS.keys).to be_empty
  end

  it "documents the file attributes" do
    Qrpm::FILE_KEYS.each { |key|
      expect(source).to match(/^#\s+#{key}:/), "#{key} is not documented"
    }
  end

  it "does not document the removed 'link' attribute" do
    expect(source).not_to match(/^#\s+link:/)
  end

  it "documents every standard directory" do
    Qrpm::STANDARD_DIRS.each { |dir|
      expect(source).to match(/^#\s+#{dir}\s/), "#{dir} is not documented"
    }
    expect(source).not_to include "vartmpdir"
  end
end
