require_relative '../lib/commands'

RSpec.describe Commands::Deploy do
  it 'parses --no-substitutes correctly' do
    args = ['deploy', '--no-substitutes', '-m', '/foo']
    cmd = Commands::Deploy.new(args)

    expect(cmd.args['no-substitutes']).to eq(true)
  end

  it 'parses --show-trace correctly' do
    args = ['deploy', '--show-trace', '-m', '/foo']
    cmd = Commands::Deploy.new(args)

    expect(cmd.args['show-trace']).to eq(true)
  end

  it 'parses --debug correctly' do
    args = ['deploy', '-t', 'dns', '--debug', '-m', '/foo']
    cmd = Commands::Deploy.new(args)

    expect(cmd.args['debug']).to eq(true)
  end
end
