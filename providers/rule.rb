require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

include DiptablesHandlerDefiner
include DiptablesDelayedApply

action :add do
    Chef::Log.debug("Adding rule to #{new_resource.table} : #{new_resource.chain} (#{new_resource.rule})")
    define_diptables_handler

    # test the new rules make sense
    test_rules

    # then apply them
    node.iptables_config.add_rule new_resource
    new_resource.updated_by_last_action true
    diptables_delayed_apply
end

private

# the name of the test chain on which we try out the rules
TEST_CHAIN_NAME = '_CHEF_IPTABLES_TEST'

def test_rules
    flush_test_chain
    shell_out! "iptables --table #{new_resource.table} --new-chain #{TEST_CHAIN_NAME}"
    begin
        new_resource.rules.each do |rule|
            test_rule = rule.gsub("-A #{new_resource.chain}", "-A #{TEST_CHAIN_NAME}")
            shell_out! "iptables --table #{new_resource.table} #{test_rule}"
        end
    ensure
        flush_test_chain
    end
end

def flush_test_chain
    shell_out "iptables --table #{new_resource.table} --flush #{TEST_CHAIN_NAME}"
    shell_out "iptables --table #{new_resource.table} --delete-chain #{TEST_CHAIN_NAME}"
end
