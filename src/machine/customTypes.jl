module customTypes

    using Dates

    export Booking,Request

    struct Booking
        start::DateTime #the start of the booking
        ending::DateTime #the end of the booking
        destination::Tuple{Int,Int} #position the user wants to go to
        preExpectedSOC::Int #expected charge before the ride has begun
        requiredSOC::Int #the state of charge needed by the car to fulfill the request
        PostExpectedSOC::Int #the expected state of charge after the vehicle is returned
        userID::Int #ID of the User
    end

    struct Request 
        start::DateTime #requested start of the booking
        ending::DateTime #requested end of the booking
        destination::Tuple{Int,Int} #position the user wants to go to
        requiredSOC::Int #the state of charge needed by the car to fulfill the request
    end

    #global bookings = Array{Vector{Booking}}

    #checks if fuel or time conflicts are given between made bookings and the request, userRequest is the request, userID is the ID of the user, booking is a 1d array of bookings; return an edited list of bookings
    function checkBookingPossible(userRequest,userID,bookings,chargePerTick)#bookings::Vector{Booking}
        #initial possibility to book, it is possible until a conflict is found
        bookingPossible = true
        #amount of bookings for the specific car
        coloumnLength = length(bookings)
        #temp is an expected state of charge for the request which is used to check if the State of Charge after the request would be sufficient for later booking
        temp = 0
        #this variable is used to keep track of the position the booking will be placed when the booking is created and put inside the array
        lastEarlierBooking = 0
        

        #going through the bookings to check if the request would be possible
        for i in 1:coloumnLength
            #the initial state of charge
            SOC = 0
            thisBooking = bookings[i]
            #checking the possibility to schedule depending on the timely arrangement
            if checkTimeOverlap(userRequest.start,userRequest.ending,thisBooking.start,thisBooking.ending) == 2 #userRequest comes after the booking
                #expected SOC at userRequest start
                SOC = thisBooking.PostExpectedSOC + Dates.value(maxSOCDifference(thisBooking,userRequest,chargePerTick))
                #check if SOC is sufficient
                if SOC < userRequest.requiredSOC
                    bookingPossible = false
                else
                    bookingPossible = (bookingPossible && true)
                end
                #minimal SOC of the userRequest 
                if temp>SOC
                    temp = SOC
                end
            elseif checkTimeOverlap(userRequest.start,userRequest.ending,thisBooking.start,thisBooking.ending) == 1 #request before booking
                #expected SOC if the request would be scheduled before this booking
                #chargePerTick needs to be given to the function '''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                SOC = temp + userRequest.requiredSOC  + Dates.value(maxSOCDifference(thisBooking,userRequest,chargePerTick))
                if SOC < userRequest.requiredSOC
                    bookingPossible = false
                else
                    bookingPossible = (bookingPossible && true)
                end
            else checkTimeOverlap(userRequest.start,userRequest.ending,thisBooking.start,thisBooking.ending) == 0 #request and booking are in conflict 
                #no booking is possible due to a time conflict
                bookingPossible = false
            end
        end

        if bookingPossible
            newBooking = customTypes.Booking(userRequest.start, userRequest.ending,userRequest.destination, temp, userRequest.requiredSOC, temp + userRequest.requiredSOC, userID)
            #bookings() = putInVectorAtPosition(bookings(carID,:),newBooking,lastEarlierBooking)
            insert!(bookings,lastEarlierBooking + 1,newBooking)
        else
            #no booking was possible
            #do nothing
        end
        return bookingPossible
    end

    #This function takes a vector and an Integer value for a position. The item at the given position inside the vector is deleted and then the vector is returned.
    function removeBooking(vector,position)
        leftVector = Vector{Booking}
        rightVector = Vector{Booking}
        for i in 0:length(vector)
            if i == position
                #do nothing
            elseif i < position
                leftVector = append!(leftVector,vector(i))
            elseif i > position
                rightVector = append!(rightVector,vector(i))
            end
        end
        leftVector = append!(leftVector,rightVector)
        return leftVector
    end

    #This function takes a vector, a position, and an item. The given item is put at the given position inside the vector. The vector will then be returned.
    function putInVectorAtPosition(vector,item,position)

        #could use insert!(array,pos,value)

        leftVector = Vector{Booking}
        rightVector = Vector{Booking}
        #vector gets split into two vectors at the given position
        for i in 0:length(vector)
            if(i < position)
                leftVector = append!(leftVector,vector(i))
            else
                rightVector = append!(rightVector,vector(i))
            end
        end
        #the vectors get put back together after adding the item between them
        leftVector = append!(leftVector,item)
        leftVector = append!(leftVector,rightVector)
        return leftVector
    end

    #This function checks how the given times are relative to each other; case = 0 times are simultaneous, case = 1 time A is after time B, case = 2 time B is after time A
    function checkTimeOverlap(startA,endA,startB,endB)
       case = 0
        if (endA-startB) > Dates.Millisecond(0) && (startB - startA) > Dates.Millisecond(0)
            case = 0
        elseif (endB-startA) > Dates.Millisecond(0) && (startA - startB) > Dates.Millisecond(0)
            case = 0
        elseif endB >= startA
            case = 1
        elseif endA >= startB
            case = 2
        end
        return case
    end

    #calculates how much the car could be charged while being idle 
    function maxSOCDifference(booking,request,chargePerTick)
        breakTime = 0
        if booking.start > request.start
            breakTime = convert(Dates.Minute, Dates.Period(booking.start - request.ending))
        elseif request.start < booking.start
            breakTime = convert(Dates.Minute, Dates.Period(request.start - booking.ending))
        else
            breakTime = Dates.Minute(-1)
        end
        return breakTime * chargePerTick
    end

end