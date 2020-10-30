require 'sinatra'
require 'net/http'
require 'uri'
require 'google/api_client'
require 'json'


get '/' do
end

get '/post' do
  # Update these to match your own apps credentials
  service_account_email = ENV['SERVICE_ACCOUNT_EMAIL'] # Email of service account

  # Get the Google API client
  client = Google::APIClient.new(
      :application_name => 'current visitor of Google Analytics post to mackerel.io',
      :application_version => '0.0.4'
  )

  key = OpenSSL::PKey::RSA.new(ENV['GOOGLE_API_KEY'].gsub("\\n", "\n"))
  client.authorization = Signet::OAuth2::Client.new(
      :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
      :audience => 'https://accounts.google.com/o/oauth2/token',
      :scope => 'https://www.googleapis.com/auth/analytics.readonly',
      :issuer => service_account_email,
      :signing_key => key,
  )

  # Request a token for our service account
  client.authorization.fetch_access_token!

  # Get the analytics API
  analytics = client.discovered_api('analytics', 'v3')

  # Get visitors of plural sites
  site_and_view_id_json = JSON.parse(ENV['SITE_AND_VIEW_ID_JSON'])

  responses = {}
  result_status = 0
  site_and_view_id_json.each do |site_and_view_id|
    site_and_view_id.each do |site, view_id|
      #p "site=#{site}、view_id=#{view_id}"

      # Execute the query, get the value like `[["1"]]`
      response = client.execute(:api_method => analytics.data.realtime.get, :parameters => {
          'ids' => "ga:" + "#{view_id}",   # Analytics view ID.
          'metrics' => "ga:activeVisitors",
      }).data.rows

      number = response.empty? ? 0 : response.first.first.to_i
      payload = [{
                     name: "current_visitors.#{site}",
                     time: Time.now.to_i,
                     value: number,
                 }].to_json

      uri = URI.parse("https://mackerel.io/api/v0/services/#{ENV['MACKEREL_SERVICE_NAME']}/tsdb")
      Net::HTTP.new(uri.host, uri.port).tap do |https|
        https.use_ssl = true
        req = Net::HTTP::Post.new(uri.request_uri).tap do |q|
          q['Content-Type'] = 'application/json'
          q['X-Api-Key'] = ENV['MACKEREL_API_KEY']
          q.body = payload
        end
        res = https.request(req)

        responses.store("#{site}", :result => {:status => res.code, :body => "#{res.body}"})
        result_status = [result_status, res.code.to_i].max
      end
    end
  end

  headers 'Content-Type' => 'application/json'
  status result_status
  resp = {
      body: responses,
  }
  resp.to_json
end

get '/sites' do
  site_and_view_id_json = JSON.parse(ENV['SITE_AND_VIEW_ID_JSON'])

  site_and_view_id_json.each do |site_and_view_id|
    site_and_view_id.each do |site,view_id|
      p "site=#{site}, viewId=#{view_id}"
    end
  end

  content_type :json
  response = {
      body: site_and_view_id_json,
  }
  response.to_json
end
