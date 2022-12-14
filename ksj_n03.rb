# frozen_string_literal: true

require 'bigdecimal'
require 'json'
require 'open-uri'
require 'active_support/core_ext/object/deep_dup'
require 'zip'

class KSJN03
  class Error < StandardError; end

  attr_reader :year, :pref_code

  def initialize(year:, pref_code:)
    @year = year
    @pref_code = pref_code
  end

  def zip_url
    y = year.to_i > 2019 ? year : year.to_s[-2, 2] # 2019年以前は最後の2文字
    "https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-#{year}/N03-#{y}0101_#{pref_code}_GML.zip"
  end

  def extract_shikuchoson_features
    feature_collection = JSON.parse(read_geojson, decimal_class: BigDecimal)
    preprocess(feature_collection['features'])
  end

  private

  def read_geojson
    URI(zip_url).open do |io|
      Zip::File.open(io) do |zip_file|
        geojson_entry = zip_file.glob('**/*.geojson').first
        geojson_entry.get_input_stream.read
      end
    end
  end

  def preprocess(features)
    code_to_features = features
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
