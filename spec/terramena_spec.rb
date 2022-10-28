# terramena_spec.rb

require_relative '../lib/commands'

RSpec.describe Terramena::Colmena do
  it 'contains --show-trace in the colmena command' do
    c = Terramena::Colmena.new('/foo', [], [])
    expect(c.send(:colmena_command, 'apply', true, true)).to match(/--show-trace/)
  end

  it 'contains --no-substitutes in the colmena command' do
    c = Terramena::Colmena.new('/foo', [], [])
    expect(c.send(:colmena_command, 'apply', true, true)).to match(/--no-substitutes/)
  end
end
