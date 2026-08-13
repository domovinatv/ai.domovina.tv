#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Stanje DOMOVINA.ai na oba storea — App Store Connect + Google Play, programski.
#
#   ./scripts/store-status.rb              # čitljiv ispis (review state, rollout, TestFlight)
#   ./scripts/store-status.rb --json       # strojni ispis (koristi nightly-build.sh)
#   ./scripts/store-status.rb --max-build  # samo najveći build/versionCode viđen na storeovima
#
# Auth: ASC .p8 API key (isti kao build-mobile-release.sh) + Play service account JSON.
# Read-only — nema PATCH/POST osim Play `edits.insert`, jer Google NEMA read-only
# endpoint za tracks; taj edit se uvijek odbaci (DELETE) prije izlaska.
require 'json'
require 'net/http'
require 'open3'
require 'uri'

ROOT       = File.expand_path('..', __dir__)
BUNDLE_ID  = 'ai.domovina'
ASC_HOST   = 'api.appstoreconnect.apple.com'
PLAY_API   = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{BUNDLE_ID}"

MODE = if ARGV.include?('--json')      then :json
       elsif ARGV.include?('--max-build') then :max_build
       else :human
       end

# ── App Store Connect ────────────────────────────────────────────────────────
def asc_token
  env = {
    'ASC_KEY_ID'    => ENV['ASC_KEY_ID']    || '25KYCN22QD',
    'ASC_ISSUER_ID' => ENV['ASC_ISSUER_ID'] || '69a6de85-f7cc-47e3-e053-5b8c7c11a4d1',
  }
  env['ASC_KEY_PATH'] = ENV['ASC_KEY_PATH'] ||
    File.join(Dir.home, '.appstoreconnect/private_keys', "AuthKey_#{env['ASC_KEY_ID']}.p8")
  out, err, st = Open3.capture3(env, 'ruby', File.join(__dir__, 'asc-token.rb'))
  raise "ASC token fail: #{err.strip}" unless st.success?

  out.strip
end

def asc_get(path, token)
  uri = URI("https://#{ASC_HOST}#{path}")
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) do |http|
    http.request(Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{token}"))
  end
  body = JSON.parse(res.body.to_s) rescue {}
  raise "ASC #{res.code} #{path}: #{body.dig('errors', 0, 'detail') || res.body}" unless res.code.to_i == 200

  body
end

def app_store_state
  token = asc_token
  app = asc_get("/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}", token).dig('data', 0)
  raise "nema appa za bundleId=#{BUNDLE_ID}" unless app

  app_id = app['id']

  vers = asc_get("/v1/apps/#{app_id}/appStoreVersions?limit=5&include=build,appStoreVersionPhasedRelease", token)
  inc  = (vers['included'] || []).each_with_object({}) { |i, h| h[[i['type'], i['id']]] = i }
  versions = (vers['data'] || []).map do |v|
    a  = v['attributes']
    br = v.dig('relationships', 'build', 'data')
    pr = v.dig('relationships', 'appStoreVersionPhasedRelease', 'data')
    {
      'version'  => a['versionString'],
      'state'    => a['appStoreState'],
      'release'  => a['releaseType'],
      'created'  => a['createdDate'],
      'build'    => br && inc[[br['type'], br['id']]]&.dig('attributes', 'version'),
      'phased'   => pr && inc[[pr['type'], pr['id']]]&.dig('attributes'),
    }
  end

  subs = asc_get("/v1/reviewSubmissions?filter%5Bapp%5D=#{app_id}&filter%5Bplatform%5D=IOS&limit=5", token)
  submissions = (subs['data'] || []).map do |s|
    { 'id' => s['id'], 'state' => s.dig('attributes', 'state'),
      'submitted' => s.dig('attributes', 'submittedDate') }
  end

  builds = asc_get(
    "/v1/builds?filter%5Bapp%5D=#{app_id}&limit=10&sort=-uploadedDate" \
    '&fields%5Bbuilds%5D=version,processingState,uploadedDate,expired', token
  )
  tf = (builds['data'] || []).map do |b|
    a = b['attributes']
    { 'build' => a['version'], 'processing' => a['processingState'],
      'uploaded' => a['uploadedDate'], 'expired' => a['expired'] }
  end

  # Review je "u letu" dok postoji submission koji nije COMPLETE, ili verzija u
  # jednom od pred-objavnih stanja.
  pending_states = %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_DEVELOPER_RELEASE
                      PENDING_APPLE_RELEASE PROCESSING_FOR_APP_STORE READY_FOR_REVIEW]
  {
    'app_id'        => app_id,
    'versions'      => versions,
    'submissions'   => submissions,
    'builds'        => tf,
    'review_pending' => submissions.any? { |s| s['state'] && s['state'] != 'COMPLETE' } ||
                        versions.any? { |v| pending_states.include?(v['state']) },
    'max_build'     => tf.map { |b| b['build'].to_i }.max || 0,
  }
end

# ── Google Play ──────────────────────────────────────────────────────────────
def play_token
  key = ENV['PLAY_SA_KEY'] || File.join(Dir.home, '.config/play-publisher/domovina-play-publisher.json')
  raise "nema Play SA ključa na #{key}" unless File.exist?(key)

  system('gcloud', 'auth', 'activate-service-account', '--key-file', key,
         out: File::NULL, err: File::NULL)
  out, err, st = Open3.capture3('gcloud', 'auth', 'print-access-token',
                                '--scopes=https://www.googleapis.com/auth/androidpublisher')
  raise "gcloud token fail: #{err.strip}" unless st.success?

  out.strip
end

def play_req(verb, url, token)
  uri = URI(url)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(verb)
  req = klass.new(uri, 'Authorization' => "Bearer #{token}")
  req['Content-Length'] = '0' if verb == :post
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) { |http| http.request(req) }
  return {} if res.body.to_s.empty?

  JSON.parse(res.body)
end

def play_state
  token = play_token
  edit = play_req(:post, "#{PLAY_API}/edits", token)
  raise "Play edits.insert: #{edit.dig('error', 'message')}" unless edit['id']

  begin
    tracks = play_req(:get, "#{PLAY_API}/edits/#{edit['id']}/tracks", token)
    raise "Play tracks: #{tracks.dig('error', 'message')}" if tracks['error']

    bundles = play_req(:get, "#{PLAY_API}/edits/#{edit['id']}/bundles", token)
    vcs = (bundles['bundles'] || []).map { |b| b['versionCode'].to_i }

    parsed = (tracks['tracks'] || []).map do |t|
      rels = (t['releases'] || []).map do |r|
        { 'name'     => r['name'],
          'codes'    => (r['versionCodes'] || []).map(&:to_s),
          'status'   => r['status'],
          # userFraction je prisutan SAMO za inProgress/halted staged rollout.
          # Odsutan + completed = 100 %.
          'fraction' => r['userFraction'] }
      end
      { 'track' => t['track'], 'releases' => rels }
    end

    prod = parsed.find { |t| t['track'] == 'production' }
    prod_rel = prod && prod['releases'].max_by { |r| r['codes'].map(&:to_i).max || 0 }
    {
      'tracks'       => parsed,
      'max_build'    => [vcs.max || 0,
                         parsed.flat_map { |t| t['releases'].flat_map { |r| r['codes'].map(&:to_i) } }.max || 0].max,
      'production'   => prod_rel,
      'rollout_pct'  => if prod_rel.nil?              then nil
                        elsif prod_rel['fraction']    then (prod_rel['fraction'].to_f * 100).round(1)
                        elsif prod_rel['status'] == 'completed' then 100.0
                        end,
    }
  ensure
    play_req(:delete, "#{PLAY_API}/edits/#{edit['id']}", token) rescue nil
  end
end

# ── Ispis ────────────────────────────────────────────────────────────────────
ios  = begin app_store_state; rescue StandardError => e then { 'error' => e.message } end
play = begin play_state;      rescue StandardError => e then { 'error' => e.message } end

result = {
  'ios'       => ios,
  'play'      => play,
  'max_build' => [ios['max_build'].to_i, play['max_build'].to_i].max,
}

case MODE
when :json
  puts JSON.pretty_generate(result)
when :max_build
  abort("GRESKA: ne mogu odrediti max build (#{ios['error'] || play['error']})") if result['max_build'].zero?
  puts result['max_build']
else
  puts '── App Store ──────────────────────────────────────────'
  if ios['error']
    puts "  GRESKA: #{ios['error']}"
  else
    ios['versions'].first(3).each do |v|
      ph = v['phased'] ? "  phased=#{v['phased']['phasedReleaseState']}" : ''
      puts format('  %-9s build %-4s %-26s %s%s', v['version'], v['build'] || '—', v['state'],
                  v['created'].to_s[0, 10], ph)
    end
    puts "  review u letu: #{ios['review_pending'] ? 'DA' : 'ne'}" \
         "  (zadnji submission: #{ios.dig('submissions', 0, 'state') || '—'})"
    puts '  TestFlight (zadnjih 5):'
    ios['builds'].first(5).each do |b|
      puts format('    build %-5s %-11s %s%s', b['build'], b['processing'],
                  b['uploaded'].to_s[0, 16], b['expired'] ? '  ISTEKAO' : '')
    end
  end
  puts
  puts '── Google Play ────────────────────────────────────────'
  if play['error']
    puts "  GRESKA: #{play['error']}"
  else
    play['tracks'].each do |t|
      if t['releases'].empty?
        puts format('  %-11s (prazno)', t['track'])
        next
      end
      t['releases'].each do |r|
        pct = if r['fraction'] then "#{(r['fraction'].to_f * 100).round(1)} %"
              elsif r['status'] == 'completed' then '100 %'
              else '—'
              end
        puts format('  %-11s %-16s vc=%-5s %-11s rollout %s', t['track'], r['name'],
                    r['codes'].join(','), r['status'], pct)
      end
    end
  end
  puts
  puts "max build/versionCode na storeovima: #{result['max_build']}"
end
