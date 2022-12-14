# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'stac'
require_relative 'n03_util'

# 以下は BigDecimal を元のまま JSON 出力するために必要
require 'active_support/core_ext/big_decimal/conversions'
require 'oj'

YEARS = [2022, 2018]
PREF_CODES = (1..47).map { |i| i.to_s.rjust(2, '0') } #=> ["01", "02", "03", ..., "47"]

TMP_DIR = File.expand_path('tmp', __dir__)
OUTPUT_DIR = File.expand_path('output', __dir__)

FileUtils.mkdir_p(TMP_DIR)
FileUtils.mkdir_p(OUTPUT_DIR)

catalog_id = 'JP-KSJ-N03'
catalog = STAC::Catalog.root(
  id: catalog_id,
  title: '日本の行政区域界',
  description: '日本の行政区域界のSTACカタログ。年・都道府県ごとにコレクションを分けている。',
  href: 'https://jp-ksj-n03-stac.sankichi.app/index.json'
)

YEARS.product(PREF_CODES) do |year, pref_code|
  print "Processing year=#{year} pref_code=#{pref_code} ..."

  zip_url = N03Util.zip_url(year:, pref_code:)
  features = N03Util.features(year:, pref_code:, cache_dir: ENV['CI'] ? nil : TMP_DIR)
  pref_name = features.first['properties']['N03_001']

  collection_id = "#{catalog_id}-#{year}0101-#{pref_code}"
  collection = STAC::Collection.from_hash(
    type: 'Collection',
    stac_version: '1.0.0',
    id: collection_id,
    title: "#{year}年#{pref_name}の行政区域界",
    description: "#{year}年1月1日時点における#{pref_name}の行政区域界のコレクション。",
    summaries: {
      N03_001: pref_name
    },
    extent: {
      spatial: {
        bbox: features.map { |f| f['bbox'] }.inject([180, 90, -180, -90]) do |res, bbox|
          [[res[0], bbox[0]].min, [res[1], bbox[1]].min, [res[2], bbox[2]].max, [res[3], bbox[3]].max]
        end
      },
      temporal: {
        interval: [[Time.new(year).utc.iso8601, (Time.new(year + 1) - 1).utc.iso8601]]
      }
    },
    license: 'CC-BY-4.0',
    providers: [
      {
        name: '国土交通省',
        description: '国土数値情報（行政区域データ）',
        roles: %w[licensor producer],
        url: 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-v3_1.html'
      },
      {
        name: 'sankichi92',
        roles: %w[processor host],
        url: 'https://github.com/sankichi92'
      }
    ],
    links: [
      {
        rel: 'derived_from',
        href: zip_url,
        type: 'application/zip',
        title: '国土数値情報（行政区域データ）'
      }
    ]
  )
  catalog.add_child(collection)

  features.each do |feature|
    item = STAC::Item.from_hash(
      feature.merge(
        'id' => "#{collection_id}-#{feature['properties']['N03_007']}",
        'assets' => {
          'data' => {
            'href' => zip_url,
            'type' => 'application/zip',
            'roles' => %w[data]
          }
        }
      )
    )
    item.datetime = Time.new(year)
    collection.add_item(item)
  end

  puts ' done'
end

catalog.export(
  'output',
  writer: STAC::FileWriter.new(hash_to_json: ->(hash) { Oj.dump(hash) })
)
