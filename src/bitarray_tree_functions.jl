using StatsBase


struct Node
    id::Int16
    item_ids::Array{Int16,1}
    transactions::BitArray{1}
    children::Array{Node,1}
    mother::Node
    supp::Int

    function Node(id::Int16, item_ids::Array{Int16,1}, transactions::BitArray{1})
        children = Array{Node,1}(0)
        nd = new(id, item_ids, transactions, children)
        return nd 
    end

    function Node(id::Int16, item_ids::Array{Int16,1}, transactions::BitArray{1}, mother::Node, supp::Int)
        children = Array{Node,1}(0)
        nd = new(id, item_ids, transactions, children, mother, supp)
        return nd 
    end
end


struct Rule 
    p::Array{Int16,1}
    q::Int16
    supp::Float64  
    conf::Float64 
    lift::Float64 

    function Rule(node::Node, mask::BitArray{1}, supp_dict::Dict{Array{Int16,1}, Int}, num_transacts::Int)
        p = node.item_ids[mask]
        supp = node.supp/num_transacts 
        conf = supp/supp_dict[node.item_ids[mask]]
        unmask = .!mask
        q_idx = findfirst(unmask)
        q = node.item_ids[q_idx]
        lift = conf/supp_dict[node.item_ids[unmask]]

        rule = new(p, q, supp, conf, lift)
        return rule 
    end
end 


# @code_warntype Node(Int16(1), Int16[1], trues(3))
n1 = Node(Int16(1), Int16[1], trues(3))

# @code_warntype Node(Int16(1), Int16[1, 2], trues(3), n1)
n2 = Node(Int16(1), Int16[1, 2], trues(3), n1, 1)
n3 = Node(Int16(1), Int16[1, 3], trues(3), n1, 1)
n4 = Node(Int16(1), Int16[1, 4], trues(3), n1, 1)
n5 = Node(Int16(1), Int16[1, 5], trues(3), n1, 1)
n6 = Node(Int16(1), Int16[1, 6], trues(3), n1, 1)
n7 = Node(Int16(1), Int16[2, 3], trues(3), n1, 1)
n8 = Node(Int16(1), Int16[2, 4], trues(3), n1, 1)
n9 = Node(Int16(1), Int16[2, 5], trues(3), n1, 1)
n10 = Node(Int16(1), Int16[2, 6], trues(3), n1, 1)


push!(n1.children, n2)
push!(n1.children, n3)
push!(n1.children, n4)
push!(n1.children, n5)
push!(n1.children, n6)
push!(n1.children, n7)
push!(n1.children, n8)
push!(n1.children, n9)
push!(n1.children, n10)

function has_children(nd::Node)
    res = length(nd.children) > 0
    res 
end

@code_warntype has_children(n1)


function younger_siblings(nd::Node)
    n_sibs = length(nd.mother.children)
    return view(nd.mother.children, (nd.id + 1):n_sibs)
end

@code_warntype younger_siblings(n1.children[1])
younger_siblings(n1.children[1])


function update_support_cnt!(supp_dict::Dict, nd::Node)
    supp_dict[nd.item_ids] = nd.supp 
end

# This function is used internally and is the workhorse of the frequent()
# function, which generates a frequent itemset tree. The growtree!() function 
# builds up the frequent itemset tree recursively.
function growtree!(nd::Node, minsupp, k, maxdepth)
    sibs = younger_siblings(nd)

    for j = 1:length(sibs)
        transacts = nd.transactions .& sibs[j].transactions
        supp = sum(transacts)
        
        if supp ≥ minsupp
            items = zeros(Int16, k)
            items[1:k-1] = nd.item_ids[1:k-1]
            items[end] = sibs[j].item_ids[end]
            
            child = Node(Int16(j), items, transacts, nd, supp)
            push!(nd.children, child)
        end
    end
    # Recurse on newly created children
    maxdepth -= 1
    if maxdepth > 1
        for kid in nd.children 
            growtree!(kid, minsupp, k+1, maxdepth)
        end
    end
end 

@code_warntype growtree!(n2, 1, 3, 3)
growtree!(n2, 1, 3, 3)



function get_unique_items{M}(transactions::Array{Array{M, 1}, 1})
    dict = Dict{M, Bool}()

    for t in transactions
        for i in t
            dict[i] = true
        end
    end
    uniq_items = collect(keys(dict))
    return sort(uniq_items)
end

t = [["a", "b"], 
     ["b", "c", "d"], 
     ["a", "c"],
     ["e", "b"], 
     ["a", "c", "d"], 
     ["a", "e"], 
     ["a", "b", "c"],
     ["c", "b", "e"]]

@code_warntype get_unique_items(t);
@time get_unique_items(t);


# This function is used internally by the frequent() function to create the 
# initial bitarrays used to represent the first "children" in the itemset tree.
function occurrence(transactions::Array{Array{String, 1}, 1}, uniq_items::Array{String, 1})
    n = length(transactions)
    p = length(uniq_items)

    itm_pos = Dict(zip(uniq_items, 1:p))
    res = falses(n, p)
    for i = 1:n 
        for itm in transactions[i]
            j = itm_pos[itm]
            res[i, j] = true
        end
    end
    res 
end

unq = get_unique_items(t)
@code_warntype occurrence(t, unq)
@time occurrence(t, unq)


"""
    frequent(transactions, minsupp, maxdepth)

This function creates a frequent itemset tree from an array of transactions. 
The tree is built recursively using calls to the growtree!() function. The 
`minsupp` and `maxdepth` parameters control the minimum support needed for an 
itemset to be called "frequent", and the max depth of the tree, respectively 
"""
function frequent(transactions::Array{Array{String, 1}, 1}, uniq_items, minsupp, maxdepth)
    occ = occurrence(transactions, uniq_items)
    
    # Have to initialize `itms` array like this because type inference 
    # seems to be broken for this otherwise (using v0.6.0)
    itms = Array{Int16,1}(1) 
    itms[1] = -1
    id = Int16(1)
    transacts = BitArray(0)
    root = Node(id, itms, transacts)
    n_items = length(uniq_items)

    # This loop creates 1-item nodes (i.e., first children)
    for j = 1:n_items
        supp = sum(occ[:, j])
        if supp ≥ minsupp
            nd = Node(Int16(j), Int16[j], occ[:, j], root, supp)
            push!(root.children, nd)
        end
    end
    n_kids = length(root.children)

    # Grow nodes in breadth-first manner
    for j = 1:n_kids
        growtree!(root.children[j], minsupp, 2, maxdepth)
    end
    root 
end


t = [["a", "b"], 
     ["b", "c", "d"], 
     ["a", "c"],
     ["e", "b"], 
     ["a", "c", "d"], 
     ["a", "e"], 
     ["a", "b", "c"],
     ["c", "b", "e", "f"]]

unq = get_unique_items(t)

@code_warntype frequent(t, unq, 0.01, 3)
xtree1 = frequent(t, unq, 0.01, 4)


function prettyprint(node::Node, k::Int = 0)
    if has_children(node)
        for nd in node.children 
            print("k = $(k + 1): ")
            println(nd.item_ids)
        end
        for nd in node.children
            prettyprint(nd, k+1)
        end
    end
end

prettyprint(xtree1)



function randstring(n::Int, len::Int = 16)
    vals = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", 
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
    upper = map(uppercase, vals)
    append!(vals, upper)
    append!(vals, map(string, 0:9))
    res = Array{String,1}(n)
    for i = 1:n
        res[i] = join(rand(vals, len))
    end
    res
end



itemlist = randstring(25, 16);

n = 100_000
m = 25              # number of items in transactions
t = [sample(itemlist, m, replace = false) for _ in 1:n];

# @code_warntype frequent(t, 1)
@time unq2 = get_unique_items(t);
@time occ2 = occurrence(t, unq2);
@time xtree1 = frequent(t, unq2, round(Int, 0.01*n), 5);


function grow_support_dict!(supp_cnt::Dict{Array{Int16,1}, Int}, node::Node) 
    if has_children(node)
        for nd in node.children
            update_support_cnt!(supp_cnt, nd)
            grow_support_dict!(supp_cnt, nd)
        end
    end
end

# This function generates a dictionary whose keys are the frequent 
# itemsets (their integer represenations, actually), and whose values 
# are the support count for the given itemset. This function is used 
# for computing support, confidence, and lift of association rules.
function gen_support_dict(root::Node, num_transacts)
    supp_cnt = Dict{Array{Int16, 1}, Int}()
    supp_cnt[Int16[]] = num_transacts
    grow_support_dict!(supp_cnt, root)
    return supp_cnt 
end

@code_warntype gen_support_dict(xtree1, n)



t1 = [["a", "b"], 
     ["b", "c", "d"], 
     ["a", "c"],
     ["e", "b"], 
     ["a", "c", "d"], 
     ["a", "e"], 
     ["a", "b", "c"],
     ["c", "b", "e", "f"]]

@code_warntype frequent(t1, 1, 3)
un3 = get_unique_items(t1)
xtree1 = frequent(t1, unq3, 1, 4);
@code_warntype gen_support_dict(xtree1, length(t1))
xsup = gen_support_dict(xtree1, length(t1))

# Given a single node in a frequent item tree, this function generates all the 
# rules for that node. This does not include rules for the node's children.
function gen_node_rules(node::Node, supp_dict::Dict{Array{Int16,1}, Int}, k, num_transacts)
    mask = trues(k)
    rules = Array{Rule, 1}(k)
    for i = 1:k 
        mask[i] = false 
        if i > 1 
            mask[i-1] = true 
        end
        rules[i] = Rule(node, mask, supp_dict, num_transacts)
    end
    rules 
end

@code_warntype gen_node_rules(xtree1.children[1].children[1].children[1], xsup, 3, 8)

xrules = gen_node_rules(xtree1.children[1].children[1].children[1], xsup, 3, 8)


function gen_rules!(rules::Array{Rule, 1}, node::Node, supp_dict::Dict{Array{Int16, 1}, Int}, k, num_transacts)
    for child in node.children 
        rules_tmp = gen_node_rules(child, supp_dict, k, num_transacts)
        append!(rules, rules_tmp)
        if !isempty(child.children)
            gen_rules!(rules, child, supp_dict, k+1, num_transacts)
        end
    end
end

rule_arr = Array{Rule, 1}(0)
gen_rules!(rule_arr, xtree1.children[1], xsup, 2, 8)
      

function gen_rules(root::Node, supp_dict::Dict{Array{Int16, 1}, Int}, num_transacts)
    rules = Array{Rule, 1}(0)
    n_kids = length(root.children)
    if n_kids > 0
        for i = 1:n_kids 
            gen_rules!(rules, xtree1.children[i], xsup, 2, num_transacts)
        end 
    end 
    rules 
end 

xrules = gen_rules()

function rules_to_datatable(rules::Array{Rule, 1}, item_lkup::Dict{Int16, String})
    n_rules = length(rules)
    dt = DataTable(lhs = fill("", n_rules), 
                   rhs = fill("", n_rules), 
                   supp = zeros(n_rules), 
                   conf = zeros(n_rules), 
                   lift = zeros(n_rules))
    for i = 1:n_rules 
        lhs_items = map(x -> item_lkup[x], rules[i].p)
       
        lhs_string = "{" * join(lhs_items, ",") * "}"
        dt[i, :lhs] = lhs_string
        dt[i, :rhs] = item_lkup[rules[i].q]
        dt[i, :supp] = rules[i].supp
        dt[i, :conf] = rules[i].conf
        dt[i, :lift] = rules[i].lift
    end 
    dt 
end 



function apriori(transactions::Array{Array{String, 1}, 1}, supp::Float64, maxdepth::Int)
    n = length(transactions)
    uniq_items = get_unique_items(transactions)
    item_lkup = Dict{Int16, String}()
    for (i, itm) in enumerate(uniq_items)
        item_lkup[i] = itm 
    end 

    freq_tree = frequent(transactions, uniq_items, round(Int, supp * n), maxdepth)
    supp_lkup = gen_support_dict(freq_tree, n)
    rules = gen_rules(freq_tree, supp_lkup, n)
    rules_dt = rules_to_datatable(xrules, item_lkup)
    return rules_dt 
end 





# Comparing with R 
a_list = [
    ["a", "b"],
    ["a", "c"],
    ["a", "b", "c"],
    ["a", "b", "d"], 
    ["a", "c", "d"], 
    ["a", "b", "c", "d"],    
    ["a", "b", "c", "e"],
    ["b", "d", "e", "f"],
    ["a", "c", "e", "f"],
    ["b", "c", "d", "e", "f"],
    ["a", "c", "d", "e", "f"],
    ["b", "c", "d", "e", "f"]
]


xtree1 = frequent(a_list, 1, 6);
xsup = gen_support_dict(xtree1, length(a_list))

xrules = gen_rules(xtree1, xsup, 12)

apriori(a_list, 0.01, 6)

# function compute_metrics(root::Node)
#     # supp_dict = gen_support_dict(root)
# end

# function get_cousins(node::Node)
#     cousins = Array{Node,1}(0)
#     if isdefined(node, :mother) && isdefined(node.mother, :mother) 
#         for aunt in younger_siblings(node.mother)
#             for nd in aunt.children
#                 push!(cousins, nd)
#             end
#         end
#     end
#     cousins
# end

# get_cousins(xtree1.children[1])


# function prettyprint2(node::Node, k::Int)
#     if has_children(node)
#         for nd in node.children 
#             print("k = $(k + 1): ")
#             println(nd.item_ids)
#         end
#         for nd in node.children
#             if (k + 1) ≥ 1 && has_children(nd)
#                 for nd in vcat(nd.children, get_cousins(nd.children[1])) 
#                     print("k = $(k + 2): ")
#                     println(nd.item_ids)
#                 end
                
#             end
#         end
#         prettyprint2(node.children[1], k + 1)
#     end
# end

# prettyprint2(xtree1, 0)

