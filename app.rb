require 'sinatra'
require 'net/http'
require 'uri'
require 'google/api_client'


get '/' do
end

get '/post' do
  # Update these to match your own apps credentials
  service_account_email = ENV['SERVICE_ACCOUNT_EMAIL'] # Email of service account
  profile_id = ENV['PROFILE_ID'] # Analytics profile ID.

  # Get the Google API client
  client = Google::APIClient.new(
    :application_name => 'current visitor of Google Analytics post to mackerel.io',
    :application_version => '0.0.1'
  )

  key = OpenSSL::PKey::RSA.new(ENV['GOOGLE_API_KEY'].gsub("\\n", "\n"))
  client.authorization = Signet::OAuth2::Client.new(
    :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
    :audience             => 'https://accounts.google.com/o/oauth2/token',
    :scope                => 'https://www.googleapis.com/auth/analytics.readonly',
    :issuer               => service_account_email,
    :signing_key          => key,
  )

  # Request a token for our service account
  client.authorization.fetch_access_token!

  # Get the analytics API
  analytics = client.discovered_api('analytics','v3')

  # Execute the query, get the value like `[["1"]]`
  response = client.execute(:api_method => analytics.data.realtime.get, :parameters => {
    'ids' => "ga:" + profile_id,
    'metrics' => "ga:activeVisitors",
  }).data.rows

  number = response.empty? ? 0 : response.first.first.to_i
  payload = [ {
                 name: "#{ENV['WEBSITE_NAME']}.current_visitors",
                 time: Time.now.to_i,
                 value: number,
            } ].to_json

  uri = URI.parse("https://mackerel.io/api/v0/services/#{ENV['MACKEREL_SERVICE_NAME']}/tsdb")
  Net::HTTP.new(uri.host, uri.port).tap do |https|
    https.use_ssl = true
    req = Net::HTTP::Post.new(uri.request_uri).tap do |q|
      q['Content-Type'] = 'application/json'
      q['X-Api-Key'] = ENV['MACKEREL_API_KEY']
      q.body = payload
    end
    res = https.request(req)
    status res.code
    headers 'Content-Type' => 'application/json'
    body "#{res.body}"
  end
end
