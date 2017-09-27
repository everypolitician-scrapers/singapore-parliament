#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'date'
require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'
# require 'scraped_page_archive/open-uri'

class TermList < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

  field :term_urls do
    noko.css('#tbl-container li a/@href').map(&:text)
  end
end

class TermPage < Scraped::HTML
  field :id do
    name[/^(\d+)/, 1]
  end

  field :name do
    dates.xpath('../text()').text.tidy
  end

  field :source do
    url.to_s
  end

  field :start_date do
    date_parts.first
  end

  field :end_date do
    date_parts.last
  end

  field :members do
    member_table.xpath('.//tr[td]').map do |tr|
      fragment(tr => MemberRow).to_h
    end
  end

  private

  def dates
    noko.css('#session_date')
  end

  def date_parts
    dates.text.split(/\s+-\s*/, 2).map { |str| str.split('.').reverse.join('-') }
  end

  def member_table
    noko.css('table.views-table')
  end
end

class MemberRow < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

  field :id do
    '%s-%s' % [name.downcase.gsub(/[[:space:]]+/, '-'), first_seen]
  end

  field :name do
    name_and_notes[0]
  end

  field :party do
    tds[2].text.tidy.tr("'", '’') # Standardise; source has both
  end

  field :image do
    tds[1].css('img/@src').text
  end

  field :notes do
    name_and_notes[1]
  end

  field :source do
    url.to_s
  end

  field :end_date do
    notes_date if notes.to_s.include? 'Resigned on '
  end

  field :start_date do
    notes_date if notes.to_s.include? 'NMP term effective '
  end

  private

  def tds
    noko.css('td')
  end

  def first_seen
    tds[4].text.tidy[/^(\d+)/]
  end

  def name_and_notes
    tds[1].text.split('(', 2).map(&:tidy)
  end

  def notes_date
    Date.parse(notes).to_s rescue ''
  end
end

def scraper(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

def term_data(url)
  term = scraper(url => TermPage).to_h
  members = term.delete(:members).map { |mem| mem.to_h.merge(term: term[:id]) }

  warn term[:name]
  ScraperWiki.save_sqlite([:id], term, 'terms')

  members
end

START = 'http://www.parliament.gov.sg/history/1st-parliament'
data = scraper(START => TermList).term_urls.flat_map { |url| term_data(url) }
data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']

# The start dates of NPMs are removed after the MP takes their seat.
# Since the official source no longer publishes these dates,
# we're hardcoding the dates we once knew back into the scraper.
%w[
  azmoon-ahmad-13 chia-yong-yong-12 ganesh-rajaram-13
  k-thanaletchimi-13 kok-heng-leun-13 kuik-shiao-yin-12
  mahdev-mohan-13 randolph-tan-12 thomas-chua-kee-seng-12
].each do |id|
  data.select { |mem| mem[:id] == id && mem[:term] == '13' }.each do |mem|
    mem[:start_date] = '2016-03-22'
    mem[:party] = 'Nominated Member of Parliament' if mem[:party].to_s.empty?
  end
end

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[id term], data)
