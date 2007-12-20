# = Rupl
# Copyright (c) 2007 Jonathan S. Garvin (http://www.5valleys.com)
# 
# See included *README* file description and for license information.
module Rupl
  RADIAN_CONVERSION_FACTOR = 180/Math::PI
  
  class << self
    
    # Returns a hash of data for the last valid reading from the GPS receiver.
    # Contains the following fields.
    #
    # latitude:: the NMEA formatted latitude. eg. '4611.2222'
    # latitude_ns:: the hemisphere of the latitude. eg 'N'
    # longitude:: the NMEA formatted longitude. eg '08522.3333'
    # longitude_ew:: the hemisphere of the longitude. eg 'W'
    # satellite_count:: number of sattelites locked onto at time of reading
    # hdop:: horizontal dilution of position
    # altitude:: altitude
    # altitude_units:: altitude units
    # signal_utc_time:: UTC time read from satelite signal
    # local_time:: what Time.now returned at reading
    def last_known_location
      @last_known_location  
    end
    
    # Takes two hashes of NMEA formatted coordinates and returns the distance in meters
    # between the two. Each hash must contain the following fields.
    # latitude:: the latitude. eg '4611.2222' for 46 degrees 11.2222 minutes
    # latitude_ns:: the latitude hemisphere. eg 'N'
    # longitude:: the longitude. eg '08511.2222' for 85 degrees 11.2222 minutes
    # longitude_ew:: the longitude hemisphere. eg 'W'
    #
    # ==== sample
    #   Rupl.compute_distance(
    #      {:latitude => '4612.3456',:latitude_ns => 'N', :longitude => '11345.321', :longitude_ew => 'W'},
    #      {:latitude => '4523.7890',:latitude_ns => 'N', :longitude => '11342.987', :longitude_ew => 'W'}
    #   ) => 89977.2970247057
    #
    def compute_distance(first,second)
      return nil if first[:latitude].nil? or second[:latitude].nil? or first[:longitude].nil? or second[:longitude].nil?
      lat1 = nmea2degree_decimal(first[:latitude],first[:latitude_ns])/RADIAN_CONVERSION_FACTOR
      lat2 = nmea2degree_decimal(second[:latitude],second[:latitude_ns])/RADIAN_CONVERSION_FACTOR
      lng1 = nmea2degree_decimal(first[:longitude],first[:longitude_ew])/RADIAN_CONVERSION_FACTOR
      lng2 = nmea2degree_decimal(second[:longitude],second[:longitude_ew])/RADIAN_CONVERSION_FACTOR
      d = 2*Math.asin(Math.sqrt((Math.sin((lat1-lat2)/2))**2 + Math.cos(lat1)*Math.cos(lat2)*(Math.sin((lng1-lng2)/2))**2))
      # convert to meters and return
      return d*RADIAN_CONVERSION_FACTOR*60.0*1852;
    end
    
    # Takes two hashes of NMEA formatted coordinates and returns the direction in degrees
    # the second is in relation to the first.
    def compute_direction(first,second)
      return nil if (lat1 == lat2 && lng1 == lng2) or first[:latitude].nil? or second[:latitude].nil? or first[:longitude].nil? or second[:longitude].nil?
      lat1 = nmea2degree_decimal(first[:latitude],first[:latitude_ns])/RADIAN_CONVERSION_FACTOR
      lat2 = nmea2degree_decimal(second[:latitude],second[:latitude_ns])/RADIAN_CONVERSION_FACTOR
      lng1 = nmea2degree_decimal(first[:longitude],first[:longitude_ew])/RADIAN_CONVERSION_FACTOR
      lng2 = nmea2degree_decimal(second[:longitude],second[:longitude_ew])/RADIAN_CONVERSION_FACTOR
      direction = "UNK";
      distance = Math.acos(Math.sin(lat1)*Math.sin(lat2)+Math.cos(lat1)*Math.cos(lat2)*Math.cos(lng1-lng2));
      azimuth = 0;
      if (Math.sin(lng2-lng1) < 0)
        azimuth = Math.acos((Math.sin(lat2)-Math.sin(lat1)*Math.cos(distance))/(Math.sin(distance)*Math.cos(lat1)))
      else
        tmp1 = (Math.sin(lat2)-Math.sin(lat1)*Math.cos(distance))/(Math.sin(distance)*Math.cos(lat1))
        azimuth = 2*Math::PI-Math.acos(tmp1)
      end
      return 360.0 - (azimuth*(RADIAN_CONVERSION_FACTOR));
    end
    
    # Converts an NMEA formatted degree/hemisphere pair into a float. 
    #   nmea2degree_decimal('4630.000','S') => -46.5
    def nmea2degree_decimal(numeric,direction)
      float = numeric.to_f/100
      degrees = float.to_i
      decimal = (100*(float-degrees))/60
      dd = ((degrees+decimal)*(direction[/(N|E)/] ? 1 : -1))
    end
    
    # converts degrees to intercardinal directions
    #   Rupl.degrees2intercardinal(42) => 'NE'
    def degrees2intercardinal(degrees)
      case
        when (degrees < 22.5 or degrees >= 337.5) : 'N'
        when (degrees >= 22.5 and degrees < 67.5) : 'NE'
        when (degrees >= 67.5 and degrees < 112.5) : 'E'
        when (degrees >= 112.5 and degrees < 157.5) : 'SE'
        when (degrees >= 157.5 and degrees < 202.5) : 'S'
        when (degrees >= 202.5 and degrees < 247.5) : 'SW'
        when (degrees >= 247.5 and degrees < 292.5) : 'W'
        when (degrees >= 292.5 and degrees < 337.5) : 'NW'
      end
    end
    
    def register(trigger) #:nodoc:
      @triggers ||= Array.new
      @triggers << trigger unless @triggers.include?(trigger)
      start
    end
    
    def deregister(trigger) #:nodoc:
      @triggers.delete(trigger)
      stop
    end
    
    #######
    private
    #######
    
    def start
      unless @tracker and @tracker.alive?
        @tracker = Thread.new do
          IO.popen('/usr/libexec/navicore-gpsd-helper').each do |line|
            next unless line[/^\$GPGGA/]
            fields = line.split(/,/)
            # If this fix  marked as valid, update last known location,
            # otherwise, assume still near previous recorded and use it.
            if (fields[6].to_i > 0)
              @last_known_location = {
                :latitude => fields[2],
                :latitude_ns => fields[3],
                :longitude => fields[4],
                :longitude_ew => fields[5],
                :satellite_count => fields[7],
                :hdop => fields[8],
                :altitude => fields[9],
                :altitude_units => fields[10],
                :local_time => Time.now,
                :signal_utc_time => fields[1]
              }
            end 
            @triggers.each { |t| t.check(@last_known_location) unless @last_known_location.nil? }
          end
        end
      end
    end
    
    def stop
      @tracker.exit if @tracker and @triggers.empty?
    end
    
  end
  
  # == Triggers
  # Triggers run a block of code (fire) when certain location critera
  # are met based on readings from the GPS receiver. There are two types
  # of conditions under which triggers may be set to fire, Movement and
  # Hotspots.
  #
  # Each types requires a block of code to run on each fire. The block
  # must accept one argument that will be a hash of data of the current
  # location.  The provided hash contains the same keys described for
  # last_known_location, as well as some additional relevent information.
  # 
  # === Movement
  # Triggers based on movement run a block of code once when first
  # created, then again every time the GPS moves outside a set radius
  # from the last time the trigger fired. 
  # 
  # ==== Arguments
  # A hash with the following key.
  # distance:: A string that indicates the radius size to
  #            measure from the last fired location. eg. "42 feet"
  #            Accepts distances in 'meters','Kilometers','feet', and 'Miles'
  # 
  # ==== Sample
  #   Rupl::Trigger.new(:distance => '42 feet') do |data|
  #     puts "I just moved 42 feet to..."
  #     puts "Lat: #{data[:latitude_ns]+data[:latitude]}"
  #     puts "Lng: #{data[:longitude_ew]+data[:longitude]}"
  #   end
  #
  # === Hotspot Proximity
  # Hotspot triggers will not fire until the GPS reports a location inside the
  # provided radius of a provided location (hotspot). It will not fire again
  # until the GPS reports a location outside the radius, and then back inside
  # again.
  #
  # ==== Arguments
  # A options hash with the following keys.
  # distance:: (required) A string that indicates the radius size to
  #            measure from the last fired location. eg. "42 feet"
  #            Accepts distances in 'meters','Kilometers','feet', and 'Miles'
  # latitude:: (required) The NMEA formatted latitude of the hotspot. eg. '4611.2222'
  # latitude_ns:: (required) The hemisphere of the hotspot. eg. 'N'
  # longitude:: (required) The NMEA formatted longitude of the hotspot. eg. '08911.2222'
  # longitude_ew:: (required) The hemisphere of the hotspot. eg. 'W'
  # delay:: (optional) Time in seconds that the GPS must remain inside
  #         the radius before the trigger is fired. Straying outside the 
  #         radius before this time is up will cancel the trigger and
  #         reset the timer. Default is 5 seconds.
  #
  # ==== Sample
  #    Rupl::Trigger.new(
  #      :distance => '15m',
  #      :latitude => '4611.2222', :latitude_ns => 'N',
  #      :longitude => '11400.1111', :longitude_ew => 'W'
  #    ) do |data|
  #      puts "########### BULLSEYE! ############# #{data[:distance]}"
  #   end
  #
  class Trigger
    
    def initialize(opts,&block)
      @distance = string2meters(opts[:distance])
      @block = block
      @waypoint = opts if opts[:latitude]
      @last_trigger_data = Hash.new
      Rupl.register(self)
    end
    
    def check(data) #:nodoc:
      return nil if data[:latitude].nil? or data[:longitude].nil?
      computed_distance = Rupl.compute_distance(data,(@waypoint || @last_trigger_data)) 
      if @waypoint
        if computed_distance < @distance
          #inside radius of set waypoint
          @time_entered_radius = Time.now unless @time_entered_radius 
          if (!@fired and ((Time.now - @time_entered_radius) > (@delay || 5)))
            #been inside radius long enough, pull the trigger
            @block.call(data.merge(:distance => computed_distance, :set_distance => @distance))
            @fired = true
          end
        elsif @time_entered_radius
          #just exited radius of set waypoint. reset flags
          @time_entered_radius = nil
          @fired = false
        end
      elsif (@last_trigger_data[:latitude].nil? or computed_distance > @distance)
        #no set waypoint but we've moved outside radius from last trigger point, fire again
        #TODO: add :direction and :delay info to data hash 
        @block.call(data.merge(:distance => computed_distance, :set_distance => @distance))
        @last_trigger_data = data
      end
    end
    
    # Prevents future firings until +restart+ method is called.
    def stop
      Rupl.deregister(self)
    end
    
    # Resumes firing the trigger after it has been stopped.
    def restart
      Rupl.register(self)
    end
    
    #######
    private
    #######
    
    def string2meters(string)
      case
        when (string.is_a?(Integer) or string.is_a?(Float)) : string.to_f #default(meters)
        when string[/([0-9\.]+)\s?(m|Meters)$/] : $1.to_f                 #meters
        when string[/([0-9\.]+)\s?(K|k)/] : $1.to_f*1000                  #Kilometers
        when string[/([0-9\.]+)\s?(M|miles)$/] : $1.to_f*1609.344         #Miles
        when string[/([0-9\.]+)\s?(F|f)/] : $1.to_f*0.3048                #feet
      end
    end
    
  end
end