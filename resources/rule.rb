actions :add
default_action :add

attribute :table, :kind_of => String, :default => 'filter'
attribute :chain, :kind_of => String, :default => 'INPUT'
attribute :rule, :kind_of => [String, Array], :default => ''
attribute :jump, :kind_of => [String, FalseClass], :default => 'ACCEPT'
attribute :comment, :kind_of => [TrueClass, FalseClass, String], :default => true
# the query to be run to get the nodes towards which this rule will apply
attribute :query, :kind_of => [String, FalseClass], :default => false
# the placeholders inside the rule string (must be named placeholders, see http://www.ruby-doc.org/core-2.0.0/Kernel.html#method-i-format)
# mapping the placeholders name to the method's name to be run on the resulting
# node objects to retrieve the value to place there
attribute :placeholders, :kind_of => Hash, :default => {}
# if true, then will force the same Chef environment in the query
attribute :same_environment, :kind_of => [TrueClass, FalseClass], :default => false

def rules
    return @rules unless @rules.nil?
    @rule = [rule] if rule.kind_of? String
    if query
        @query = "(#{query}) AND chef_environment:#{node.chef_environment}" if same_environment
        Chef::Log.debug("Running query: #{query}, will be applied to rule #{rule} and with placeholders #{placeholders}")
        @rules = []
        if Chef::Config[:solo] && !chef_solo_search_installed?
            Chef::Application.fatal! 'This recipe uses search. Chef Solo does not support search unless you install the chef-solo-search cookbook.'
        end
        nodes = search(:node, query)
        Chef::Log.warn("No result for the query #{query}") if nodes.empty?
        Chef::Log.debug("Query results: #{nodes.inspect}")
        # sort by name to avoid reloading iptables when the search doesn't return nodes in the same order
        nodes.sort{|a, b| a.name <=> b.name}.each do |n|
            # compute the placeholders' hash for that node
            node_placeholders = Hash[placeholders.map{ |placeholder, method| [placeholder, method.split('.').inject(n, :send)] } ]
            # add one rule per node, per rule template
            rule.each do |r|
                @rules << sprintf(r, node_placeholders)
            end
        end
    else
        Chef::Application.fatal!('Invalid attributes for the DiptablesRule resource! placeholders and same_environment only make sense when used together with the query attribute') if !placeholders.empty? || same_environment
        @rules = rule
    end
    # and finally, create the actual string rules
    @rules.map! { |r| string_rule r }
end

alias_method :old_comment, :comment
def comment *args
    # we default to the name of the rule if no comment has been given, but comments haven't been disabled either
    @comment = name if @comment == true
    old_comment *args
end

private

# shamelessly copied from https://github.com/sethvargo-cookbooks/users
def chef_solo_search_installed?
    ::Search::const_get('Helper').is_a?(Class)
rescue NameError
    false
end

def string_rule rule_value
    j = jump ? " --jump #{jump}" : ''
    "-A #{chain} #{rule_value}#{j}"
end