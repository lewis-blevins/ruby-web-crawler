$stdout.sync = true

require "httparty"
require "nokogiri"
require 'sqlite3'
require 'time'

ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"

# get .txt file search keywords (into list)
file = File.open("Search Keywords.txt", "r")
content = file.read
file.close
keywords = content.split("\n")
puts "The following keywords will be searched for: " + keywords.join(", ")

# connect to database
db = SQLite3::Database.open 'Database.db'

# define URL
urlBaseToQuery = "https://newyork.craigslist.org/search/sss?query="
urlQueryToIndex = "#search=1~gallery~"
urlPostIndex = "~0"

keywords.each do |keyword|

  # loop through x pages
  pageCount = 0
  while pageCount < 1

    # create full URL
    fullURL = urlBaseToQuery + keyword + urlQueryToIndex + pageCount.to_s + urlPostIndex

    # visit website
    ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
    puts "Visiting this URL: " + fullURL
    response = HTTParty.get(fullURL,{headers: { "User-Agent" => ua},})
    html_doc = Nokogiri::HTML(response.body)

    # get URLs
    allURLs = html_doc.xpath("//a/@href").map(&:text)
    listingURLs = allURLs.reject {|item|!item.match(/\/[0-9]{6,}\.html/)}
    listingURLs = listingURLs.uniq
    puts listingURLs.length.to_s + " listing urls were found"

    # add urls to database (with timestamp)
    listingURLs.each do |url|

      time_str = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      db.execute "INSERT INTO urlsToCrawl (URL, Keyword, FoundAt, HasBeenVisited) VALUES (?, ?, ?, ?)", [url, keyword, time_str, 0]

    end

    pageCount += 1

  end

end

# remove duplicate URLs and close database
db.execute "DELETE FROM urlsToCrawl WHERE EXISTS (SELECT 1 FROM urlsToCrawl p2 WHERE urlsToCrawl.URL = p2.url AND urlsToCrawl.rowid > p2.rowid);"

# Get unvisited URLs
unvisitedURLsQuery = db.execute "SELECT URL FROM urlsToCrawl where HasBeenVisited = 0"

unvisitedURLsList = []

unvisitedURLsQuery.each do |row|
  unvisitedURLsList << row[0]
end

unvisitedURLsList.each do |currentUrl|

  puts "Visiting this URL: " + currentUrl

  # visit URL
  response = HTTParty.get(currentUrl,{headers: { "User-Agent" => ua},})
  html_doc = Nokogiri::HTML(response.body)

  # pause for 3 seconds for every iteration of loop (to avoid blocking)
  sleep(3)

  # check if listing has been removed
  deletedMessage = html_doc.at_xpath("//div[@class='removed']")
  if deletedMessage.nil?

    # scrape details
    title = html_doc.at_xpath("//title").text
    title = title.empty? ? '' : title

    postId = html_doc.xpath("//p[@class='postinginfo'][1]").text
    regexMatch = postId.match(/([0-9]{5,})/)
    postId = regexMatch ? regexMatch[1] : ''

    postedAge = html_doc.xpath("//p[@class='postinginfo reveal'][1]/time[@class='date timeago']").text
    regexMatch = postedAge.match(/([0-9\-]{10} [0-9:]{5})/)
    postedAge = regexMatch ? regexMatch[1] : ''

    updatedAge = html_doc.xpath("//p[@class='postinginfo reveal'][2]/time[@class='date timeago']").text
    regexMatch = updatedAge.match(/([0-9\-]{10} [0-9:]{5})/)
    updatedAge = regexMatch ? regexMatch[1] : ''

    puts "These details have been scraped...\nTitle: " + title + "\nPost ID: " + postId + "\nPosted at: " + postedAge + "\nUpdated at: " + updatedAge

    # enter scraped details into database, updated urlsToCrawl table
    time_str = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    db.execute "INSERT INTO listings (url, title, post_id, post_age, updated_age, visited_at) VALUES (?, ?, ?, ?, ?, ?)", [currentUrl, title, postId, postedAge, updatedAge, time_str]
    db.execute "UPDATE urlsToCrawl SET HasBeenVisited='1' WHERE URL = ?", [currentUrl]

  else

    next # skip dead listings

  end

end

db.close
