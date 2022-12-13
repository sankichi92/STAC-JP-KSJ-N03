# frozen_string_literal: true

require 'bigdecimal'
require 'json'
require 'open-uri'
require 'active_support/core_ext/object/deep_dup'
require 'zip'

module N03Util
  class Error < StandardError; end

  def self.features(year:, pref_code:, cache_dir:)
    geojson_str = read_geojson(year:, pref_code:, cache_dir:)
    geojson_hash = JSON.parse(geojson_str, decimal_class: BigDecimal)
    N03Util.preprocess(geojson_hash)
  end

  def self.read_geojson(year:, pref_code:, cache_dir:)
    cache_path = cache_dir && File.join(cache_dir, "#{pref_code}-#{year}.geojson")
    return File.read(cache_path) if cache_path && File.exist?(cache_path)

    url = zip_url(year:, pref_code:)
    geojson_str = URI(url).open do |io|
      Zip::File.open(io) do |zip_file|
        geojson_entry = zip_file.glob('**/*.geojson').first
        geojson_entry.get_input_stream.read
      end
    end
    File.write(cache_path, geojson_str) if cache_path
    geojson_str
  end

  def self.zip_url(year:, pref_code:)
    y = year.to_i > 2019 ? year : year.to_s[-2, 2] # 2019年以前は最後の2文字
    "https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-#{year}/N03-#{y}0101_#{pref_code}_GML.zip"
  end

  def self.preprocess(geojson)
    code_to_features = geojson['features']
                       .reject { |f| f['properties']['N03_007'].nil? } # 所属未定地を除く
                       .group_by { |f| f['properties']['N03_007'] } # 行政区域コードごとにまとめる

    code_to_features.map do |_, features|
      raise Error, 'Unexpected properties' if features.map { |f| f['properties'] }.uniq.size > 1

      feature = features.first.deep_dup

      if features.size > 1 # 複数の feature がある場合は Polygon をマージして MultiPolygon にする
        raise Error, 'Unexpected geometry type' if features.any? { |f| f['geometry']['type'] != 'Polygon' }

        feature['geometry']['type'] = 'MultiPolygon'
        feature['geometry']['coordinates'] = features.map { |f| f['geometry']['coordinates'] }
      end

      # `features.inject` ではなく `fature['geometry']['coordinates'].inject` にしないのは
      # type が Polygon か MultiPoligon かでブロック引数が変わってしまうため
      feature['bbox'] = features.inject([180, 90, -180, -90]) do |result, f|
        f['geometry']['coordinates'].first.inject(result) do |r, point|
          [[r[0], point[0]].min, [r[1], point[1]].min, [r[2], point[0]].max, [r[3], point[1]].max]
        end
      end

      feature
    end
  end
end
