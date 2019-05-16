include("max-num-generator.jl")
include("../star/StarAgents.jl")
include("../star/Protos.jl")

using Random
using RCall

maxnumchannel = Channel(producer);

mutable struct ScapeAgent
    a::StarAgent
    location_x::Int64
    location_y::Int64
    vision::Int64

    function ScapeAgent(
        agent_id::String,
        metabolic_rate::Int64,
        sugar_level,
        alive::Bool,
        proto_id::Int64,
        location_x::Int64,
        location_y::Int64,
        vision::Int64)
        starAgent = StarAgent(agent_id, metabolic_rate, sugar_level, alive,
            proto_id)
        return new(starAgent, location_x, location_y, vision)
    end
end

function fetch_best_location(ag_obj, sugscape_obj)
    """
    Returns a tuple representing the location of the sugarscape cell that is
    not occupied and has the highest sugarlevel in the Von-Neumann neighborhood.
    Returns null if no such cell can be found.
    """
    low_row = max(1, ag_obj.location_x - ag_obj.vision)
    low_col = max(1, ag_obj.location_y - ag_obj.vision)

    hi_row = min(size(sugscape_obj, 1), ag_obj.location_x + ag_obj.vision)
    hi_col = min(size(sugscape_obj, 2), ag_obj.location_y + ag_obj.vision)

    # try
    #     @assert all(map(x -> x > 1, [low_row, low_col, hi_row, hi_col]))
    # catch
    #     println("--------------------------")
    #     println("low_row:", string(low_row), " hi_row:", string(hi_row),
    #           " low_col:", string(low_col), " hi_col:", string(hi_col))
    #     println("---------------------------")
    # end
    poss_cells = [sugscape_obj[x, y] for x in low_row:hi_row,
                  y in low_col:hi_col
                  if (!sugscape_obj[x, y].occupied &
                      (sugscape_obj[x, y].sugar_level > 0))]
    # println("Here are the potential cells")
    # x = readline()
    # println([(cellobj.location_x, cellobj.location_y, cellobj.a.sugar_level)
    #          for cellobj in poss_cells])
    if length(poss_cells) > 0
        a_suglevels = [cellobj.sugar_level for cellobj in poss_cells]
        a_cells =[cellobj for cellobj in poss_cells
                  if cellobj.sugar_level == maximum(a_suglevels)]
        return((a_cells[1].location_x, a_cells[1].location_y))
    else
        return(nothing)
    end    
end ## end fetch_best_location

function locate_move_feed!(agobj, sugscape_obj, arr_agents, arr_protos, timeperiod)
    """
    For a given agent, performs the feeding operation first. If sugar is not 
    available within the agent or in conjunction with current location, moves
    to a new location, if available. If not available, dies. 
    
    TODO: in a future version, will have a clock to keep of number of time
    periods that have elapsed in starvation mode, and performs death when
    a threshold has passed.
    """
    # println("Performing locate-move-feed on agent:", string(agobj.a.agent_id), "")
    
    if(agobj.a.alive)
        if agobj.a.sugar_level >= agobj.a.metabolic_rate
            agobj.a.sugar_level = agobj.a.sugar_level - agobj.a.metabolic_rate
            # println("Agent ", string(agobj.a.agent_id), " just drew from its self ",
            #       "sugar reserve!")
            ## x = readline() 
        elseif sugscape_obj[agobj.location_x,
                            agobj.location_y].sugar_level +
                                agobj.a.sugar_level >= agobj.a.metabolic_rate

            agobj.a.sugar_level = sugscape_obj[agobj.location_x,
                                                 agobj.location_y].sugar_level +
                                                     agobj.a.sugar_level - agobj.a.metabolic_rate
            # println("Agent ", string(agobj.a.agent_id), " loaded up at its current location!")
            sugscape_obj[agobj.location_x, agobj.location_y].sugar_level = 0
            sugscape_obj[agobj.location_x, agobj.location_y].occupied = true
            sugscape_obj[agobj.location_x, agobj.location_y].agent_id = agobj.a.agent_id
            ## x = readline()
        else ## need to move or borrow from proto
            ## identify best location
            new_location = fetch_best_location(agobj, sugscape_obj)
            if isnothing(new_location)
                ## no food available at current location and no new source
                ## of food available, so see if withdrawal from proto is possible
                probj = fetch_specific_proto_obj(arr_protos,
                                            agobj.a.proto_id)
                needed_amount = agobj.a.metabolic_rate - agobj.a.sugar_level
                if agobj.a.proto_id > 0 && (probj.sugar_level >
                                                needed_amount)
                    agobj.a.sugar_level = 0
                    probj.sugar_level -= needed_amount
                    push!(probj.ledger_transactions,
                          Transaction(needed_amount, timeperiod, "withdrawal",
                                      agobj.a.agent_id))
                else
                    ## otherwise, set alive status to false
                    sugscape_obj[agobj.location_x,
                                 agobj.location_y].occupied = false
                    sugscape_obj[agobj.location_x,
                                 agobj.location_y].agent_id = "-"
                    agobj.a.alive = false
                    agobj.location_x, agobj.location_y = -1, -1 
                    # println("Agent ", string(agobj.a.agent_id), " starved to death!")
                    ## x = readline()
                end

            else
                ## move to and load from the new cell location
                sugscape_obj[agobj.location_x,
                             agobj.location_y].occupied = false
                sugscape_obj[agobj.location_x,
                             agobj.location_y].agent_id = "-"
                agobj.location_x, agobj.location_y = new_location[1], new_location[2]
                sugscape_obj[agobj.location_x, agobj.location_y].sugar_level -=
                    sugscape_obj[agobj.location_x, agobj.location_y].sugar_level +
                    agobj.a.sugar_level - agobj.a.metabolic_rate 
                sugscape_obj[agobj.location_x,
                             agobj.location_y].occupied = true
                sugscape_obj[agobj.location_x,
                             agobj.location_y].agent_id = agobj.a.agent_id 
            end ## move and consume 
        end ## agobj.a.sugar_level >= agobj.a.metabolic_rate
    else ## agent is dead
        # println("Tried to animate a dead agent: ", string(agobj.a.agent_id))
        ## x = readline()
    end 
end ## locate_move_feed!()


function life_check!(arr_agents)
    """
    Remove agents from the arr_agents whose sugarlevel <= 0.
    """
    for agobj in arr_agents
        if agobj.a.sugar_level < 0
            agobj.location_x = -1
            agobj.location_y = -1
            agobj.alive = false
            agobj.a.proto_id = -1
        end
    end
    # println("Number of agents: ", string(length(arr_agents)))
    # println("Number of dead agents: ", string(count([!agobj.a.alive for agobj in arr_agents])))
    arr_agents = [agobj for agobj in arr_agents if agobj.a.alive]
    # if length(arr_agents) < 1
    #     println("It appears that all agents have died!")
    # end
    return(arr_agents)
end

function compute_Gini(arr_agents)
    arr_suglevels = [agobj.a.sugar_level for agobj in
                     arr_agents]
    R"library(ineq)"
    gini = R"ineq($arr_suglevels, type='Gini')"[1]
    try
        @assert gini >= 0.0 && gini <= 1.0
    catch
        ## println("Came across a nonsensical Gini value: ", string(gini))
        # readline()
    end

    # println(gini)
    return(gini)    
end

function perform_birth_inbound_outbound!(arr_agents, sugscape_obj, birth_rate, 
                                         inbound_rate, outbound_rate, 
                                         vision_distrib, metabol_distrib, 
                                         suglvl_distrib)
    """
    Implements the births, inbound migration, and outbound migration by adding new agents 
    (births and inbound) and removing agents (outbound).
    
    The current version implements births and in-bound migrations jointly by adding a 
    number of agents added = Int(ceil((birth_rate + inbound_rate) * no_agents))
    number of agents removed = Int(ceil(outbound_rate * no_agents)).

    Modifies arr_agents and sugscape_obj in place.
    """
    arr_agents = life_check!(arr_agents)
    ## determine how many agents to add and remove
    no_agents = length(arr_agents)
    no_to_add = Int(ceil((birth_rate + inbound_rate) * no_agents))
    no_to_remove = Int(ceil(outbound_rate * no_agents))
    
    ## remove the required number of randomly-chosen agents
    ## and set their corresponding sugarscape cells' occupied status to false
    ## and the agent_id to "-".
    shuffle!(arr_agents)
    
    for count in 1:no_to_remove
        agobj = pop!(arr_agents)
        
        if agobj.location_x == -1 && agobj.location_y == -1 
            println("Caught an inconsistent agent!")
            println(agobj)
            ## readline()
        else
            sugscape_obj[agobj.location_x, agobj.location_y].occupied = false
            sugscape_obj[agobj.location_x, agobj.location_y].agent_id = "-"
            
        end
    end

    # ## identify potential locations on sugarscape for adding agents
    arr_empty_locations = [(cellobj.location_x, cellobj.location_y) 
                           for cellobj in sugscape_obj
                           if cellobj.occupied == false]

    if(size(arr_empty_locations)[1] < no_to_add)
        ## select a random sample of locations
        # println("Not enough cells available for adding all of the required",
        #         " number of agents")
        no_to_add = size(arr_empty_locations)[1]
    end ## end if not enough cells available

    arr_locations = sample(arr_empty_locations, no_to_add, replace=false)
    highest_id = -99
    try
        @assert length(arr_agents) > 0
        ## highest agent id
        highest_id = maximum([agobj.a.agent_id for agobj in arr_agents])        
        ## add agents to the chosen locations
        highest_id_idx = findall(x->x==highest_id, AGENT_IDS)[1]
        arr_agent_ids = AGENT_IDS[[agid for agid in
            (highest_id_idx+1):(highest_id_idx + no_to_add)]]
        arr_new_agents = [ScapeAgent(arr_agent_ids[index],
                                rand(metabol_distrib),
                                rand(suglvl_distrib),
                                true,
                                -1,
                                arr_locations[index][1],
                                arr_locations[index][2],
                                rand(vision_distrib))
                          for index in 1:no_to_add]

        ## set the new cell locations' occupied status to true
        # for loc_tpl in arr_locations
        #     sugscape_obj[loc_tpl[1], loc_tpl[2]].occupied = true
        # end
        
        for agobj in arr_new_agents
            sugscape_obj[agobj.location_x, agobj.location_y].occupied = true
            sugscape_obj[agobj.location_x, agobj.location_y].agent_id = agobj.a.agent_id
        end
        append!(arr_agents, arr_new_agents)
    catch
        # println("Caught the assertion!")
        # println(length(arr_agents))
        highest_id = take!(maxnumchannel)
        # println("Fetched a new maxnum: ", string(highest_id))
    end

    arr_empty_locations = [(cellobj.location_x, cellobj.location_y) 
                           for cellobj in sugscape_obj
                           if cellobj.occupied == false]

end ## perform_birth_inbound_outbound!()
