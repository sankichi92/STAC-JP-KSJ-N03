# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'stac'
require_relative 'ksj_n03'

# 以下は BigDecimal を元のまま JSON 出力するために必要
require 'active_support/core_ext/big_decimal/conversions'
require 'oj'

YEARS = [2022, 2018]
PREF_CODES = (1..47).map { |i| i.to_s.rjust(2, '0') } #=> ["01", "02", "03", ..., "47"]

OUTPUT_DIR = File.expand_path('output', __dir__)
FileUtils.mkdir_p(OUTPUT_DIR)

catalog_id = 'jp-ksj-n03'
catalog = STAC::Catalog.root(
  id: catalog_id,
  title: '日本の行政区域界',
  description: '日本の行政区域界のSTACカタログ。年・都道府県ごとにコレクションを分けている。',
  href: 'https://jp-ksj-n03-stac.sankichi.app/index.json'
)

YEARS.product(PREF_CODES) do |year, pref_code|
  print "Processing year=#{year} pref_code=#{pref_code} ..."

  ksjn03 = KSJN03.new(year:, pref_code:)
  features = ksjn03.extract_shikuchoson_features
  pref_name = features.first['properties']['N03_001']

  collection = STAC::Collection.from_hash(
    type: 'Collection',
    stac_version: '1.0.0',
    id: "#{catalog_id}-#{year}0101-#{pref_code}",
    title: "#{year} #{pref_name}",
    description: "#{year}年#{pref_name}の行政区域界コレクション。",
    extent: {
      spatial: {
        bbox: [
          features.map { |f| f['bbox'] }.inject([180, 90, -180, -90]) do |res, bbox|
            [[res[0], bbox[0]].min, [res[1], bbox[1]].min, [res[2], bbox[2]].max, [res[3], bbox[3]].max]
          end
        ]
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
        name: '@sankichi92',
        description: 'STACカタログへの加工とホスティングを実施',
        roles: %w[processor host],
        url: 'https://github.com/sankichi92'
      }
    ],
    links: [
      {
        rel: 'derived_from',
        href: ksjn03.zip_url,
        type: 'application/zip',
        title: '国土数値情報ダウンロードサイトの加工元コンテンツ'
      }
    ]
  )
  catalog.add_child(collection)

  features.each do |feature|
    item = STAC::Item.from_hash(
      feature.merge(
        'id' => "#{catalog_id}-#{year}0101-#{feature['properties']['N03_007']}",
        'properties' => feature['properties'].merge(
          'title' => "#{feature['properties']['N03_003']}#{feature['properties']['N03_004']}",
          'datetime' => Time.new(year).iso8601
        ),
        'assets' => {
          'data' => {
            'title' => '加工元データ',
            'description' => "加工元となった#{year}年#{pref_name}の行政区域データ。GML、Shapefile、GeoJSON を含む ZIP ファイル。",
            'href' => ksjn03.zip_url,
            'type' => 'application/zip',
            'roles' => %w[data]
          }
        }
      )
    )
    collection.add_item(item)
  end

  puts ' done'
end

catalog.export(
  'output',
  writer: STAC::FileWriter.new(hash_to_json: ->(hash) { Oj.dump(hash) })
)
