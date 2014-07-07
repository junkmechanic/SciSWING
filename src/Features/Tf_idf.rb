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

def accumulate_idf(document, word, section=true)
  # This will initiate the recursive function to calculate the idf for each
  # word in the dependency parse of the sentence that ispart of the sub tree
  # whoese root node is word. The section flag specifies whether the idf value
  # used will be from webBase or the sectional idf.
  # Here, document, sentence and word should all be hashes.
  value, num = recursive_compute(document, word, section)
  if value == 0.0 then
    return 0.0
  else
    return value / num
  end
end

def recursive_compute(document, word, section)

  term = word["word"].downcase
  if $stoplist.stopwords.include?(term.downcase) or /.*[0-9].*/.match(term)
    num = 0
    value = 0.0
  else
    num = 1
    if section
      value = get_section_idf(document, term)
      puts "secidf value for #{term} is #{value}"
    else
      value = if $IDF.has_key?(term) then $IDF[term] else 0.0 end
      if value == 0.0
        puts "---------------------------- #{term} not found in webBase"
      else
        puts "webidf value for #{term} is #{value}"
      end
    end
  end
  # Now recurse into the children.
  if word.has_key?("children")
    word["children"].each do |child|
      val, n = recursive_compute(document, child, section)
      value += val
      num += n
    end
  end
  return value, num

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

      freq = document["term_freq"][verb]
      web_idf = accumulate_idf(document, sentence["dep_parse"][0], false)
      sec_idf = accumulate_idf(document, sentence["dep_parse"][0], true)
      puts "#{rank}. #{sentence["sentence"]}\nVerb: #{verb}\ttf=#{freq}\tweb_idf=#{web_idf}\tsec_idf=#{sec_idf}"
      if subj_node
        word = subj_node["word"].downcase
        freq = document["term_freq"][word]
        web_idf = accumulate_idf(document, subj_node, false)
        sec_idf = accumulate_idf(document, subj_node, true)
        puts "Subject: #{subj_node["word"]}\ttf=#{freq}\tweb_idf=#{web_idf}\tsec_idf=#{sec_idf}"
      else
        puts "Subject : <none>"
      end
      if obj_node
        word = obj_node["word"].downcase
        freq = document["term_freq"][word]
        web_idf = accumulate_idf(document, obj_node, false)
        sec_idf = accumulate_idf(document, obj_node, true)
        puts "Oject: #{obj_node["word"]}\ttf=#{freq}\tweb_idf=#{web_idf}\tsec_idf=#{sec_idf}"
      else
        puts "Object : <none>"
      end
    end
    puts "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
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
