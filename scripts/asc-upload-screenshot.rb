#!/usr/bin/env ruby
# Upload jednog screenshota na App Store Connect.
# Args: <appStoreVersionLocalizationId> <screenshotDisplayType> <file.png>
# Env: ASC_TOKEN (bearer). Reuse postojeći set istog displayType ako postoji.
require 'json'; require 'net/http'; require 'uri'; require 'digest'
LOC, DTYPE, FILE = ARGV
TOKEN = ENV.fetch('ASC_TOKEN')
BASE = 'https://api.appstoreconnect.apple.com'

def req(method, url, body: nil, headers: {}, raw: nil)
  uri = URI(url)
  klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, put: Net::HTTP::Put}[method]
  r = klass.new(uri)
  headers.each { |k, v| r[k] = v }
  r.body = raw ? raw : (body ? JSON.generate(body) : nil)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(r) }
  [res.code.to_i, res.body]
end
def auth(extra = {}); {'Authorization' => "Bearer #{TOKEN}"}.merge(extra); end

# 1) nađi ili kreiraj appScreenshotSet
code, body = req(:get, "#{BASE}/v1/appStoreVersionLocalizations/#{LOC}/appScreenshotSets", headers: auth)
sets = JSON.parse(body)['data'] rescue []
set = sets.find { |s| s['attributes']['screenshotDisplayType'] == DTYPE }
setid = set && set['id']
unless setid
  code, body = req(:post, "#{BASE}/v1/appScreenshotSets",
    headers: auth('Content-Type' => 'application/json'),
    body: {data: {type: 'appScreenshotSets', attributes: {screenshotDisplayType: DTYPE},
      relationships: {appStoreVersionLocalization: {data: {type: 'appStoreVersionLocalizations', id: LOC}}}}})
  abort "set create #{code}: #{body}" unless code == 201
  setid = JSON.parse(body)['data']['id']
end
puts "set=#{setid}"

# 2) rezerviraj screenshot
data = File.binread(FILE)
code, body = req(:post, "#{BASE}/v1/appScreenshots",
  headers: auth('Content-Type' => 'application/json'),
  body: {data: {type: 'appScreenshots', attributes: {fileName: File.basename(FILE), fileSize: data.bytesize},
    relationships: {appScreenshotSet: {data: {type: 'appScreenshotSets', id: setid}}}}})
abort "reserve #{code}: #{body}" unless code == 201
sh = JSON.parse(body)['data']
shid = sh['id']
ops = sh['attributes']['uploadOperations']

# 3) upload binarno po operacijama
ops.each do |op|
  off = op['offset']; len = op['length']
  hdrs = {}; (op['requestHeaders'] || []).each { |h| hdrs[h['name']] = h['value'] }
  code, _ = req(op['method'].downcase.to_sym, op['url'], headers: hdrs, raw: data[off, len])
  abort "upload chunk #{code}" unless code.between?(200, 299)
end

# 4) commit s md5
md5 = Digest::MD5.hexdigest(data)
code, body = req(:patch, "#{BASE}/v1/appScreenshots/#{shid}",
  headers: auth('Content-Type' => 'application/json'),
  body: {data: {type: 'appScreenshots', id: shid, attributes: {uploaded: true, sourceFileChecksum: md5}}})
abort "commit #{code}: #{body}" unless code == 200
puts "OK uploaded #{File.basename(FILE)} id=#{shid}"
