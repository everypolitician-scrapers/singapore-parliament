#!/bin/env ruby
# encoding: utf-8

require 'date'
require 'nokogiri'
require 'pry'
require 'scraperwiki'
require 'scraped_page_archive/open-uri'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def date_from(str)
  Date.parse(str).to_s rescue ''
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def scrape_list(url)
  noko = noko_for(url)
  noko.css('#tbl-container li a/@href').each do |href|
    link = URI.join url, href
    scrape_term(link)
  end
end

def scrape_term(url)
  noko = noko_for(url)

  # Term info
  dates = noko.css('#session_date')
  term_name = dates.xpath('../text()').text.tidy
  term = {
    id: term_name[/^(\d+)/, 1],
    name: term_name,
    source: url.to_s,
  }
  term[:start_date], term[:end_date] = dates.text.split(/\s+-\s*/, 2).map { |str| str.split('.').reverse.join("-") }
  warn term[:name]
  ScraperWiki.save_sqlite([:id], term, 'terms')


  # Members
  noko.css('table.views-table').xpath('.//tr[td]').each do |tr|
    tds = tr.css('td')
    first_seen = tds[4].text.tidy[/^(\d+)/]
    name, notes = tds[1].text.split('(', 2).map(&:tidy)
    data = {
      id: "%s-%s" % [name.downcase.gsub(/[[:space:]]+/,'-'), first_seen],
      name: name,
      party: tds[2].text.tidy.tr("'","’"), # Standardise; source has both
      image: tds[1].css('img/@src').text,
      term: term[:id],
      notes: notes,
      source: url.to_s,
    }
    data[:image] = URI.join(url, data[:image]).to_s unless data[:image].to_s.empty?
    data[:end_date] = date_from(data[:notes]) if data[:notes].to_s.include? 'Resigned on '
    data[:start_date] = date_from(data[:notes]) if data[:notes].to_s.include? 'NMP term effective '

    # The start dates of NPMs are removed after the MP takes their seat.
    # That is, we once had these start dates but now we haven't.
    # Since the official source no longer publishes these dates,
    # we're hardcoding them into the scraper.
    term_13_nmps = %w(
      azmoon-ahmad-13
      chia-yong-yong-12
      ganesh-rajaram-13
      k-thanaletchimi-13
      kok-heng-leun-13
      kuik-shiao-yin-12
      mahdev-mohan-13
      randolph-tan-12
    )
    if term[:id] == '13' && term_13_nmps.include?(data[:id])
      data[:start_date] = '2016-03-22'
      data[:party] = 'Nominated Member of Parliament' if data[:party].to_s.empty?
    end

    ScraperWiki.save_sqlite([:id, :term], data)
  end
end

scrape_list('http://www.parliament.gov.sg/history/1st-parliament')
