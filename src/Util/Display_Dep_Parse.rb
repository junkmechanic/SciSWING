#/usr/bin/ruby
# encoding: UTF-8

### 20/05/2014 - Ankur

require 'json'

def print_parse root
  string = root["word"] + "\n"
  return string + get_children(root)
end

def get_children node
  tstring = ""
  if node.has_key?("children")
    node["children"].each do |child|
      tstring += (" " * 3 * child["level"]) + "#{child["level"]}-#{child["word"]}  -  (#{child["dep"]})\n"
      tstring += get_children child
    end
  end
  return tstring
end

ARGF.each do |l_JSN|

  $g_JSON = JSON.parse l_JSN
  $g_JSON["corpus"].each do |l_Article|
    l_Article["top_sentences"].each do |rank, sentence|
      puts "#{rank}. #{sentence["sentence"]}"
      if sentence["dep_parse"].length > 1
        # Hopefully it will never come to this
        error_msg = "There seem to be multiple root nodes (or orphaned nodes) "\
          "in doc: #{document["actual_doc_id"]}, sentence-id : #{sentence["id"]}"
        puts "WARNING : #{error_msg}"
      else
        puts print_parse(sentence["dep_parse"][0])
      end
    end
  end

end
