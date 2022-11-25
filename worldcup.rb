require "uri"
require "net/https"
require "json"
require "pp"
require "icalendar"
require "tzinfo"
require "time"
require "active_support"
require "active_support/core_ext"

CACHE = {
  matches: "tmp/matches-#{Time.now.strftime("%Y-%m-%dT%H:%M")}.json",
  teams: "tmp/teams-#{Time.now.strftime("%Y-%m-%dT%H:%M")}.json"
}

DATA =
  CACHE
    .keys
    .each_with_object({}) do |key, memo|
      cache_path = CACHE.fetch(key)

      memo[key] = if File.exist?(cache_path)
        JSON.parse(File.read(cache_path), symbolize_names: true)
      else
        JSON
          .parse(
            Net::HTTP.get_response(URI.parse("https://worldcupjson.net/#{key}")).body,
            symbolize_names: true
          )
          .tap { |data| File.open(cache_path, "w") { |f| f << JSON.dump(data) } }
      end
    end

def get_team(country)
  groups = DATA.dig(:teams, :groups)

  groups.each do |group|
    group
      .fetch(:teams)
      .each do |team|
        if team.fetch(:country) == country
          result = { group: group.fetch(:letter) }.merge(team)
          return result
        end
      end
  end

  nil
end

def get_summary(datum)
  teams =
    [datum.dig(:home_team, :country), datum.dig(:away_team, :country)].map { |c| get_team(c) }
      .compact

  vs = teams.map { |team| team.fetch(:name) }.join(" v ").presence
  group = teams.map { |team| team.fetch(:group) }.first
  stage = datum[:stage_name]

  if stage == "First stage"
    "#{vs} (Group #{group})"
  elsif vs.present?
    "#{vs} (#{stage})"
  else
    "TBD (#{stage})"
  end
end

def get_description(datum)
  pp datum
  nil
end

cal = Icalendar::Calendar.new
cal.append_custom_property("X-WR-TIMEZONE", "UTC")

DATA
  .fetch(:matches)
  .each do |datum|
    cal.event do |e|
      e.dtstart = Time.iso8601(datum.fetch(:datetime)).utc
      e.summary = get_summary(datum)
      e.location = datum.values_at(:venue, :location).join(", ")
    end
  end

cal.publish

File.open("worldcup.ics", "w") { |f| f << cal.to_ical }
