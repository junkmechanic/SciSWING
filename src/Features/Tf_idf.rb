#/usr/bin/ruby
# encoding: UTF-8

### 25/05/2014 - Ankur

# TODO: This script

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/..')
$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../..')

require 'json'
require 'set'
require 'lib/ptb_tokenizer'
require 'lib/stopwords/StopList'

$IDF = Hash.new

def prepare_IDF
  idf_dir = "/home/ankur/devbench/scientific/SciSWING/lib/webBase/"
  Dir.glob(idf_dir + "idf*.tsv") do |idf_file|
    File.open(idf_file, "r") do |f|
      f.each_line do |line|
        begin
          word = /(.+)\t(.+)/.match(line)[1]
          idf = /(.+)\t(.+)/.match(line)[2]
          $IDF[word] = idf.to_f
        rescue Exception => e
        end
      end
    end
  end
end

def compute_word_counts document

  # This will calculate the term frequencies of all the words in the document.
  # All the words will be saved in a set for each section and serialized, for
  # caching, into lists. This will help in the calculation of sectional -idf
  # scores.
  # NOTE For now, I have not used the stemmer. Once the pipeline is ready, will
  # see if that improves the performance drastically.
  term_freq = Hash.new
  $stoplist = StopList.new
  document["content"].each do |section|
    word_set= Set.new
    section["sentences"].values.each do |sentence|
      reduced = PTBTokenizer.tokenize(sentence.downcase)
      wordlist = ($stoplist.filter reduced).split
      # Should stem here
      # the call to the 'uniq' method might be redundant since its a set merge
      word_set.merge wordlist.uniq

      # update the term_freq hash
      wordlist.each do |term|
        # Should stem here
        if term_freq.has_key? term
          term_freq[term] += 1
        else
          term_freq[term] = 1
        end
      end
    end
    section["word_set"] = word_set.to_a
  end
  document["term_freq"] = term_freq

end

def get_section_idf(document, word)

  # First find out the section frequency of the word in the document
  sf = 0
  document["content"].each do |section|
    if section["word_set"].include?(word)
      sf += 1
    end
  end
  num = document["content"].length
  if sf > 0
    return -( Math.log(sf) - Math.log(num) )
  else
    return 0
  end

end

def accumulate_idf(document, word)
  # This will initiate the recursive function to calculate the idf for each
  # word in the dependency parse of the sentence that is part of the sub tree
  # whoese root node is word.
  # Here, document and word should both be hashes.
  web_value, sec_value, num = recursive_compute(document, word)
  if web_value == 0.0 then
    ret_web = 0.0
  else
    ret_web = web_value / num
  end
  if sec_value == 0.0 then
    ret_sec = 0.0
  else
    ret_sec = sec_value / num
  end
    return ret_web, ret_sec
end

def recursive_compute(document, word)

  term = word["word"].downcase
  if $stoplist.stopwords.include?(term.downcase) or /.*[0-9].*/.match(term)
    num, web_value, sec_value = 0, 0.0, 0.0
  else
    num = 1
    sec_value = get_section_idf(document, term)
    web_value = if $IDF.has_key?(term) then $IDF[term] else 0.0 end
  end
  # Now recurse into the children.
  if word.has_key?("children")
    word["children"].each do |child|
      web_val, sec_val, n = recursive_compute(document, child)
      web_value += web_val
      sec_value += sec_val
      num += n
    end
  end
  return web_value, sec_value, num

end

def extract_features document

  # Use the dependency parse to get the verb, subject and object phrases and
  # compute the tf_idf statistics for each.
  document["top_sentences"].each do |rank, sentence|
    # the sentence variable is a hash by iteslf with "sentence" and "dep_parse"
    # and "id" keys
    if sentence["dep_parse"].length > 1
      # Hopefully it will never come to this
      error_msg = "There seem to be multiple root nodes (or orphaned nodes) "\
        "in doc: #{document["actual_doc_id"]}, sentence-id : #{sentence["id"]}"
      puts "WARNING : #{error_msg}"
    else
      verb = sentence["dep_parse"][0]["word"].downcase
      # now that we have the word, we can get the tf, the idf can be extracted
      # from both webBase idfs and also calculating the sectional idf
      subj_node = find_node(sentence, "subj")
      obj_node = find_node(sentence, "obj")

      freq = if document["term_freq"].has_key?(verb) then document["term_freq"][verb] else 0.0 end
      web_idf = if $IDF.has_key?(verb) then $IDF[verb] else 0.0 end
      sec_idf = get_section_idf(document, verb)
      sentence["features"] = {"verb_tf"=>freq,"verb_web_idf"=>web_idf,"verb_sec_idf"=>sec_idf}

      if subj_node
        word = subj_node["word"].downcase
        freq = if document["term_freq"].has_key?(word) then document["term_freq"][word] else 0.0 end
        web_idf, sec_idf = accumulate_idf(document, subj_node)
        sentence["features"].merge!({"subj_tf"=>freq,"subj_web_idf"=>web_idf,"subj_sec_idf"=>sec_idf})
      end

      if obj_node
        word = obj_node["word"].downcase
        freq = if document["term_freq"].has_key?(word) then document["term_freq"][word] else 0.0 end
        web_idf, sec_idf = accumulate_idf(document, obj_node)
        sentence["features"].merge!({"obj_tf"=>freq,"obj_web_idf"=>web_idf,"obj_sec_idf"=>sec_idf})
      end
    end
  end

end

def find_node(sentence, pattern)
  root = sentence["dep_parse"][0]
  # Matching regexp
  if /#{pattern}/.match(root["dep"])
    return root
  end
  queue = root["children"]
  while queue.length > 0
    child = queue.shift
    if /#{pattern}/.match(child["dep"])
      return child
    else
      if child.has_key?("children")
        child["children"].each do |small_child|
          queue.push(small_child)
        end
      end
    end
  end
  return nil
end

ARGF.each do |l_JSN|

  # Get all the IDF values from the web corpus
  prepare_IDF

  $g_JSON = JSON.parse l_JSN

  # Compute all the word frequencies and document (section) frequencies.
  $g_JSON["corpus"].each do |l_Article|
    compute_word_counts l_Article
    extract_features l_Article
  end

  puts JSON.generate $g_JSON
end
