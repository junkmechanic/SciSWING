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
  idf_file = "/home/ankur/devbench/scientific/SciSWING/lib/idf.tsv"
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

def compute_word_counts document

  # This will calculate the term frequencies of all the words in the document.
  # All the words will be saved in a set for each section and serialized, for
  # caching, into lists. This will help in the calculation of sectional -idf
  # scores.
  # NOTE For now, I have not used the stemmer. Once the pipeline is ready, will
  # see if that improves the performance drastically.
  term_freq = Hash.new
  stoplist = StopList.new
  document["content"].each do |section|
    word_set= Set.new
    section["sentences"].values.each do |sentence|
      reduced = PTBTokenizer.tokenize(sentence.downcase)
      wordlist = (stoplist.filter reduced).split
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
      # from bother google idfs and also calculating the sectional idf
      subj_node = find_node(sentence, "subj")
      obj_node = find_node(sentence, "obj")

      web_idf = if $IDF.has_key?(verb) then $IDF[verb] else nil end
      sec_idf = get_section_idf(document, verb)
      puts "#{sentence["sentence"]}\nVerb: #{verb}\t\tweb_idf=#{web_idf}\tsec_idf=#{sec_idf}"
      if subj_node
        freq = document["term_freq"][subj_node["word"]]
        word = subj_node["word"].downcase
        web_idf = if $IDF.has_key?(word) then $IDF[word] else nil end
        sec_idf = get_section_idf(document, word)
        puts "Subject: #{subj_node["word"]}\ttf=#{freq}\tweb_idf=#{web_idf}\tsec_idf=#{sec_idf}"
      else
        puts "Subject : <none>"
      end
      if obj_node
        freq = document["term_freq"][obj_node["word"]]
        word = obj_node["word"].downcase
        web_idf = if $IDF.has_key?(word) then $IDF[word] else nil end
        sec_idf = get_section_idf(document, word)
        puts "Oject: #{obj_node["word"]}\ttf=#{freq}\tweb_idf=#{web_idf}\tsec_idf=#{sec_idf}"
      else
        puts "Object : <none>"
      end
    end
  end

end

def find_node(sentence, pattern)
  root = sentence["dep_parse"][0]
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

  #puts JSON.pretty_generate $g_JSON
end
