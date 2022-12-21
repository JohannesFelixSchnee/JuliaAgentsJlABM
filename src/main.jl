include("machine/customTypes.jl")
# using Pkg
# Pkg.add("Statistics")

using .customTypes
using .customTypes:Request
using Dates
using Agents
using Random
using InteractiveDynamics
using GLMakie
using Statistics: mean


#initilize the global time
global time = DateTime(2022,01,01,11,0,0) #when set to now() the real-time and date are used
#amount of all requests, failed and successfull
global requestAmount = 0
#amount of all failed requests
global failedRequests = 0
#sum of happiness values
global happinessSum = 0
#dimension of the grid; dim(x,y), x and y coordinates
global dims = (3,3)
#initial charge each car starts with
global standartInitialChargeCar = 10
#toogles initial charge variation
global initialChargeVariation = true
#maximal charge a car can have
global maxChargeCar = 100
#amount of charge that gets added each tick when charging a car
global stationChargePerTick = 10
#amount of charge that gets subtracted each tick when riding a car
global chargeConsumptionPerTick = 10
#amount of cars in the model
global numberOfCars = 8
#total number of user in the system(including deleted ones)
global numberOfUser = 0
#defines the maximum on how long a booking can be created in advance, in minutes
global maxAdvanceBookingTime = 120
#defines minimum on how long a booking can be created in advance, in minutes
global minAdvanceBookingTime = 1
#defines how long the duration of one booking could be
global maximalBookingTime = 180
#initialize 2D Array of Bookings
global schedules = Array{Vector{Main.customTypes.Booking}}(undef,numberOfCars)
#initial Happiness of the user
global InitialHappiness = 2
#vector of the amounts of the average charges of each step
global averageCharges = Vector{Float64}[]
#vector for each charge in each step
global stepCharges = 0
#current number of the step
global stepNumber = 0

#=
Remaining Bugs:
While the ride, user and car position are different(did not appear again  so it may be fixed already)
"Key not found error", User gets deleted but is still being called in the car - mostly breaks at key 17(first user)
=#

#definition of the three types of agents

#=
Agent definition for the Electric Cars
=#
mutable struct Car <: AbstractAgent
    #identifier of the agent
    id::Int
    #position inside on the grid
    pos::Tuple{Int,Int}
    #current amount of charge
    charge::Int
    #maximal amount charge can become
    maxCharge::Int
    #states if car is in use; true = in use, false = not in use
    inUse::Bool
    # Id of the Charging station
    station::Int
end

#=
Agent definition for the User 
destination contains the position the user wants to move to
=#
mutable struct User <: AbstractAgent
    #identifier of the agent
    id::Int
    #position inside on the grid
    pos::Tuple{Int,Int}
    #position the user wants to go to (can be replaced by using the request)
    #destination::Tuple{Int,Int}
    #request type, contains needed data for the schedule
    request::Request
    #contains the current amount of happiness, which can only be decreased; initial value = 0, max = 10 (user is completely happy), min = 0 
    happiness::Int
    #contains if the destination was reached; initial = false (not reached yet), true (reached already, is returning)
    reachedDestination::Bool
    #indicates if the request was turned into a booking request, yes = true, no = false
    booked::Bool
    #indicates if the user has to be deleted
    dead::Bool
    #nextPos
    #nextPos::Tuple{Int,Int}
end

#=
Agent definition for the Charging station 
destination contains the position the user wants to move to
=#
mutable struct ChargingStation <: AbstractAgent
    #identifier of the agent
    id::Int
    #position on the grid
    pos::Tuple{Int,Int}
    #amount the car is charged each tick while charging
    chargePerTick::Int
    #optional variable could be used if the station has an internal charge which could be used before using power from the grid
    #charge :: Int
    #optional variable could be used to count the amount of power used from the grid
    #powerUsedFromTheGrid :: Int
end

# function chargeFun(agent)
#     if isinstance(agent,Car)
#        return agent.charge / numberOfCars
#     else 
#         0.0
#         return 1
#     end
# end

function main()
    #define which data should be collected
    chargeFun(agent) = if agent isa Car agent.charge/numberOfCars else 0.0 end
    # chargeFun(agent) = agent.pos[1]*2
    # x(agent) = agent.pos[1]
    #initialize the model
    model = initialize()
    adata = [(chargeFun,sum)]
    #create the model plot and display it
    fig, p=abmexploration(
        model;
        agent_step! = Agents_step!,
        model_step! = Model_step!,
        ac = groupcolor, am = groupmarker, as = 12,
        adata, alabel =["Test Label"]
    )
    # display(fig)
    # display(scene)
    display(fig)
end

properties = (
    #empty for now
)

#initialization of the agents and the field

function initialize(n_cars = numberOfCars,charge_car = standartInitialChargeCar,maxCharge = maxChargeCar) #1.n_cars = 8, 2.n_user=0, 3. dims = (3,3)
    #create model
    space = GridSpace(dims, periodic = true)
    #the scheduler defined in which order the agents are processed, here it is random.
    scheduler = Schedulers.randomly
    model = AgentBasedModel(Union{Car,User,ChargingStation},space;scheduler,warn = false)
    #add cars
    for n in 1:n_cars
        #initialize the vector  for the bookings
        schedules[n] = Booking[]
        #initial charge of the car
        if(initialChargeVariation)
            #initial charge of the car variates from 1 to charge_car*3 if initialChargeVariation is true
            charge = rand(1:(charge_car*3)) - 1
        else
            #initial charge of the car, equal to standartInitialChargeCar if initialChargeVariation is false
            charge = charge_car
        end
        #initialy the car is not in use
        inUse = false
        #create x position
        x = rand(1:dims[1])
        #create y position
        y = rand(1:dims[2])
        #Position for the car and the station
        thisPos = (mod(n-1 , 3) + 1,((n-1) ÷ 3)+1)
        #new car gets created
        newCar = Car(n,thisPos,charge,maxCharge,inUse,n + numberOfCars)
        #create charging stationChargePerTick
        newStation = ChargingStation(n_cars+n,thisPos,stationChargePerTick)
        #each position has one charging station, so one car per position
        add_agent!(newCar,thisPos,model)
        add_agent!(newStation,thisPos,model)
    end

    #create one initial user; just for testing
    global numberOfUser = numberOfUser + 1
    #createID
    newUserID = n_cars*2 + numberOfUser
    #create x position
    # xU = rand(1:(dims[1]))
    #for testing booking if no car is in the same position
    xU = 3
    #create y position
    # yU = rand(1:(dims[2]))
    #for testing booking if no car is in the same position
    yU = 3
    #createRequest
    request = createRandomRequest(xU,yU)
    userTest = User(newUserID,(xU,yU),request,InitialHappiness,false,false,false)
    add_agent_pos!(userTest, model)
    return model
end



#Agent behavior

#function for checking if the car is at an charging station
function stationInPosition(pos, model)
    ids = ids_in_position(pos, model)
    i = findfirst(id -> model[id] isa ChargingStation ,ids)
    if isnothing(i)
        return false
    else
        return true
    end
end

#function for checking if a user is at the car
function userInPosition(pos, model)
    ids = ids_in_position(pos, model)
    i = findfirst(id -> model[id] isa User ,ids)
    if isnothing(i)
        return false
    else
        return true
    end
end

#function for checking if a car is at the user
function carInPosition(pos, model)
    ids = ids_in_position(pos, model)
    i = findfirst(id -> model[id] isa Car && !model[id].inUse,ids)
    if isnothing(i)
        return false
    else
        return true
    end
end

#function for getting the chargingStation at the given position
function getStation(pos, model)
    ids = ids_in_position(pos, model)
    i = findfirst(id -> model[id] isa ChargingStation,ids)
    return model[ids[i]]
end

#function for getting the user at the given position
function getUser(pos, model)
    ids = ids_in_position(pos, model)
    i = findfirst(id -> model[id] isa User ,ids)
    return i
end

#function for getting the car in the given position
function getCar(pos, model)
    ids = ids_in_position(pos, model)
    i = 0
    for a in ids
        if model[a] isa Car && !model[a].inUse
            i = a
        end
    end
    #i = findfirst(id -> model[id] isa Car && !model[id].inUse,ids)
    return i
end

function chargeCar(car,model)
    station = getStation(car.pos,model)
        temp = car.charge + station.chargePerTick
        if temp < car.maxCharge
            car.charge = temp
        else
            car.charge = car.maxCharge
        end
end

#=
defines how the cars act on the model
=#
function Agents_step!(car :: Car, model)
    global stepCharges = stepCharges + car.charge
    if car.inUse
        #the first booking is always the next booking, due to the vector being sorted
        nextBooking = schedules[car.id][1]
        #ride
        #car is in use and takes a ride
        if nextBooking.start < time && nextBooking.ending > time
            userOfCurrentBooking = model[nextBooking.userID]
            if userOfCurrentBooking.reachedDestination && carHasToReturn(car,model)
                if car.pos == model[nextBooking.userID].pos
                else
                    println("here!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",car.pos,model[nextBooking.userID].pos)
                end
                moveToDestination(car,userOfCurrentBooking,model[car.station].pos,model)
                car.charge = car.charge - chargeConsumptionPerTick
            elseif !userOfCurrentBooking.reachedDestination
                if car.pos == model[nextBooking.userID].pos
                else
                    println("here!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",car.pos,model[nextBooking.userID].pos) 
                end
                moveToDestination(car,userOfCurrentBooking,nextBooking.destination,model)
                car.charge = car.charge - chargeConsumptionPerTick
            end

        else
            #ride has ended
            #delete the finished booking and the user
            println("User ",schedules[car.id][1].userID, " finished")
            model[schedules[car.id][1].userID].suicide = true
            #kill_agent!(model[schedules[car.id][1].userID],model)
            popfirst!(schedules[car.id])

            #if the booking is over the car is not in use anymore
            car.inUse = false
        end
    elseif !car.inUse && !isempty(schedules[car.id]) && bookingDue(car)
            #the car is not in use yet but has scheduled bookings, where one of which is about to start
            #the first booking is always the next booking, due to the vector being sorted by time
            nextBooking = schedules[car.id][1] #else use : instead of one and then check thisCarsBookings[1]
            
            keyMissing = false 
            try
                userOfCurrentBooking = model[nextBooking.userID]
            catch y
                println("ACHTUNG!!!!")
                keyMissing = true
            end

            if !keyMissing
                #booking starts
                #inUse is set to true, then the car and user move
                car.inUse = true
                userOfCurrentBooking = model[nextBooking.userID]
                #checking if the user position still is the same as the car position
                if car.pos == userOfCurrentBooking.pos
                    println("no problems",car.id," ",userOfCurrentBooking.id)
                else
                    println("here!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",car.pos,userOfCurrentBooking.pos,car.id," ",userOfCurrentBooking.id)
                end

                moveToDestination(car,userOfCurrentBooking,nextBooking.destination,model)
            end
    else
        #car is its station
        if stationInPosition(car.pos,model) #car is at its station and charges
            chargeCar(car,model)
        else #car has no station, this case should not occur
            id = nextid(model)
            chargePerTick = stationChargePerTick
            station = ChargingStation(id,car.pos,chargePerTick)
            add_agent_pos!(station,model)
        end
    end
    return
end


#function for checking if a booking starts now
function bookingDue(car)
    nextBooking = schedules[car.id][1]
    if nextBooking.start == time
        println("true")
        return true
    else
        println("false")
        return false
    end
end

#=
defines how the user acts on the model
=#
function Agents_step!(user :: User, model)
    if(user.suicide)
        return
        #kill_agent!(user,model)
    end
    #booking request and drive is to be added
    if user.booked #The user already has a booking
        # println("booked")
        if user.request.destination == user.pos
            user.reachedDestination = true
        end
    else #The user has not a booking yet
        #get the car at the position if there is one
        tmpCar = 0
        if carInPosition(user.pos,model)
            tmpCar = getCar(user.pos,model) 
        end

        wasBookingMade = false
        #check if the car at the position is available for booking
        if !(tmpCar == 0) && requestPossibleFromNow(user.request,time,model[tmpCar],model)
            closeCar = model[tmpCar]
            #check if the car already has bookings or not
            if isempty(schedules[closeCar.id]) && closeCar.pos == user.pos
                #The car has no bookings and can be booked without checking
                userRequest = user.request
                bookingTest = customTypes.Booking(userRequest.start, userRequest.ending,userRequest.destination, 0, userRequest.requiredSOC, 0 + userRequest.requiredSOC, user.id)
                push!(schedules[closeCar.id],bookingTest)
                user.booked = true
                wasBookingMade = true
            elseif closeCar.pos == user.pos
                #the car at the position already has bookings, but more could be added
                wasBookingMade = customTypes.checkBookingPossible(user.request,user.id,schedules[closeCar.id],model[closeCar.id + numberOfCars].chargePerTick)
                #check if the booking was possible
                if wasBookingMade
                    user.booked = true
                end
            end
        end

        #if the user where not able to book a car at its location other position are checked
        if !wasBookingMade
            #because the user has to move to get to a car its happiness value gets reduced by one
            user.happiness = user.happiness - 1
            #check for other cars

            #local variable for tracking if a booking could be made 
            possibleBookingFound = false
            #id of the car that could be booked; if 0 there was no booking
            bookedCarID = 0
            #a list containing ids of cars that could be available for booking in the user's vicinity. The cars are added to the list without checking their availability.
            possibleCars = Int[]
            #create a list of the nearby agents' ids; r is the radius a user is willing to walk
            for neighbor in nearby_ids(user, model,1)
                if model[neighbor] isa Car && !model[neighbor].inUse
                    push!(possibleCars,neighbor)
                end
            end
            #the initial try was to use nearby agents like this, but the radius does not change
            # for neighbor in nearby_agents(user, model, 1)
            #     if neighbor isa Car && !neighbor.inUse
            #         push!(possibleCars,neighbor.id)
            #     end
            # end

            #i is a temporary buffer for the position of the id which belongs to the chosen car
            i = 1
            #as long as no booking was made or the entire list was inspected
            while !possibleBookingFound && i < (length(possibleCars) + 1)
                if model[possibleCars[i]].pos == user.request.destination
                    #ignore this option, because if it is possible it would already have been checked earlier
                else
                    #The possibility of booking is reviewed; if it was successful the car is saved and the while-loop ends
                    possibleBookingFound = customTypes.checkBookingPossible(user.request,user.id,schedules[possibleCars[i]],model[possibleCars[i] + numberOfCars].chargePerTick)
                    bookedCarID = possibleCars[i]
                    #could be unnecessary
                    if possibleBookingFound
                        break
                    end
                end
                i = i + 1
            end
            wasBookingMade = possibleBookingFound
            tmpCar = bookedCarID
        end
        #if the booking was possible, print it and move the user to the booked car; if booking was not possible the user gets even unhappier and gets deleted
        if wasBookingMade
            println("got booked")
            user.booked = true
            #move the User to the position
            bookedCar = model[tmpCar]
            move_agent!(user,bookedCar.pos, model)
        else
            user.happiness = user.happiness - 1
            #no car is available
            println("No available car here!")
            println("User ",user.id, " finished")
            #delete user
            user.suicide = true
            #kill_agent!(user,model)
        end

    end
    return
end

#checks if the car has the necessary charge until the start of the request, without looking at booking time conflicts
function requestPossibleFromNow(request,time,car,model)
    breaktime = -1
    if 0 < convert(Dates.Minute, Dates.Period(request.start - (time + Dates.Minute(minAdvanceBookingTime)))).value
        breakTime = convert(Dates.Minute, Dates.Period(request.start - time)).value
    else
        breakTime = -1
    end
    return ((breakTime * (model[car.id + numberOfCars].chargePerTick)) > request.requiredSOC)
end

#=
defines how the charging stations act on the model
=#
function Agents_step!(car :: ChargingStation, model)
    #the charging station does not have an independent behavior, but e.g. it could be changed that the charging is arranged by the station, or the electricity price is monitored.
    #could have an integrated battery it charges when empty would use the power grid and keep track of the consumption
    return
end

#stepping function for the model
function Model_step!(model)
    #amount of time that the global time gets increased each step
    #time increased by one minute, can be changed according to needs
    global stepNumber = stepNumber + 1
    temp = time + Dates.Minute(1)
    global time = temp
    # stepCharges = []
    #test print of time
    println(temp)

    #check if a user should be added at this moment 
    #possibilityTest = customerPossiblity()
    #test print if user would be added
    #println(possibilityTest)

    if customerPossiblity()
        createRandomUser(model)
        println("new User")
    end

    
    #calculate the average of the charges and write it into the vector
    if isempty(averageCharges)
        if numberOfCars != 0
            global averageCharges = [stepCharges/numberOfCars]
        else 
            global averageCharges = [0]
        end
    else
        if numberOfCars != 0
            # global averageCharges[stepNumber] = stepCharges/numberOfCars
            push!(averageCharges, stepCharges/numberOfCars)
        else
            push!(averageCharges, 0)
        end
    end
    global stepCharges = 0

    for id in Agents.schedule(model)
        agent = model[id]
        if agent isa User && agent.suicide
            kill_agent!(agent,model)
        end
    end

    return
end

#function for checking if the car and user have to return to make it back to the station before the end of the booking. 
function carHasToReturn(car,model)
    carStation = model[car.station]
    distanceToStation = abs(car.pos[1]-carStation.pos[1]) + abs(car.pos[2]-carStation.pos[2])
    booking = schedules[car.id][1]
    timeLeft = convert(Dates.Minute, Dates.Period(booking.ending - time)).value
    if timeLeft > distanceToStation
        return false
    else
        return true
    end
end

#calculates how many minutes are between the request and the booking. 
function maxMinuteDifference(booking,request,chargePerTick)
    breakTime = 0
    if booking.start > request.start
        return convert(Dates.Minute, Dates.Period(time.start - booking.ending)).value
    elseif request.start < booking.start
        return convert(Dates.Minute, Dates.Period(request.start - booking.ending)).value
    else
        return 0
    end
    return breakTime
end

function createRandomUser(model)
    #create one initial user; just for testing
    global numberOfUser = numberOfUser + 1
    #create a new ID for the new user.
    userID = numberOfCars*2 + numberOfUser
    #create x position
    xU = rand(1:(dims[1]))
    #create y position
    yU = rand(1:(dims[2]))
    #create a new random Request
    request = createRandomRequest(xU,yU)
    userTest = User(userID,(xU,yU),request,InitialHappiness,false,false,false)
    add_agent!(userTest, model)
end

function createRandomRequest(xPosition,yPosition)
    #creates a random destination on the field, which is different from the current position.
    destination = (rand(1:dims[1]),rand(1:dims[2]))
    while destination == (xPosition,yPosition)
        destination = (rand(1:dims[1]),rand(1:dims[2]))
    end
    #calculate the needed state of charge for the request
    requiredSOC = abs(destination[1]-xPosition) + abs(destination[2] - yPosition)
    #create a random value, for the request start and duration.
    timeDiffOne = rand(minAdvanceBookingTime:maxAdvanceBookingTime)
    timeDiffTwo = rand(1:maximalBookingTime)
    startT = time
    startT = startT + Dates.Minute(timeDiffOne)
    endT = startT
    endT = endT + Dates.Minute(timeDiffTwo)
    request = Request(startT,endT,destination,requiredSOC)
    return request
end


#changes the position of the car and user to be closer to their goal 
function moveToDestination(car,user,destination,model)
    # println(destination)
    # println(car.pos)
    # println(user.pos)
    newPos = car.pos
    if destination[1] > newPos.pos[1]
        println(destination,car.pos,user.pos,"1")
        newPos = (newPos[1] + 1, newPos[2])
        move_agent!(user,newPos, model)
        move_agent!(car,newPos, model)
    elseif destination[1] < car.pos[1]
        println(destination,car.pos,user.pos,"2")
        newPos = (newPos.pos[1] - 1, newPos.pos[2])
        move_agent!(user,newPos, model)
        move_agent!(car,newPos, model)
    else
        if destination[2] > car.pos[2]
            println(destination,car.pos,user.pos,"3")
            newPos = (newPos[1],newPos[2] + 1)
            move_agent!(user,newPos, model)
            move_agent!(car,newPos, model)
        elseif destination[2] < car.pos[2]
            newPos = (newPos[1],newPos[2] - 1)
            println(destination,car.pos,user.pos,"4")
            move_agent!(user,newPos, model)
            move_agent!(car,newPos, model)
        else
            println(destination,car.pos,user.pos,"5")
            user.reachedDestination = true
        end
    end
    #user and car position gets increased/decreased in one coordinate to be closer to their destination
    return
end

#function for checking if a user appears with the given (changing) chance
#a function could be added to provide a realistic chance of usage over a day
function customerPossiblity()
    #=
    provisional funtion!!!!
        A random number from 0 to 1000 is generated
        The function returns as true if the random number is smaller than the result of the function
        The function is hill shaped(flipped parabloa). Its roots are on x=0 and x=24 and the peak is at x=12
        The highest point is y=144.
        Because the random number is between 0 and 1000 there is a maximal chance of 15% to return true at 12:00 to 12:59 (15% each Minute)
    =#
    if (rand(0:1000)) < ((-1*^(Dates.hour(time) - 12,2)) + 144)*2
        return true
    else
        return false
    end
end

#Visualisation

#set the color of an agent, based on its type
function groupcolor(agent)
    if agent isa User
        return :orange
    elseif agent isa Car 
        return :blue
    else
        return :red
    end
end

#set the shape of an agent, based on its type
function groupmarker(agent)
    if agent isa User
        return :rect
    elseif agent isa Car 
        return :utriangle
    else
        return :circle
    end
end


#run main
main()
