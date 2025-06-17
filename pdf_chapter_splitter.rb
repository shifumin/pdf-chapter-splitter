#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "fileutils"
require "pdf-reader"
require "hexapdf"

class PDFChapterSplitter
  INVALID_FILENAME_CHARS = %r{[/:\*\?"<>|]}
  CHAPTERS_DIR = "chapters"

  def initialize
    @options = parse_options
    @pdf_path = ARGV[0]
    validate_input!
  end

  def run
    execute_with_error_handling
  end

  # Public API methods

  def filter_chapters_by_depth(chapters, depth)
    chapters = chapters.dup
    build_parent_child_relationships(chapters)
    select_chapters_at_depth(chapters, depth)
  end

  def extract_chapters
    reader = PDF::Reader.new(@pdf_path)
    extract_chapters_from_reader(reader)
  rescue PDF::Reader::MalformedPDFError => e
    error_exit "Error: The PDF file appears to be corrupted. #{e.message}"
  rescue StandardError => e
    error_exit "Error reading PDF: #{e.message}"
  end

  def split_pdf(chapters)
    HexaPDF::Document.open(@pdf_path) do |doc|
      context = create_split_context(doc, chapters)
      process_all_pdf_sections(doc, context)
    end
  end

  private

  # Main execution flow
  def execute_with_error_handling
    perform_splitting
  rescue StandardError => e
    handle_runtime_error(e)
  end

  def perform_splitting
    log_start_processing

    chapters = prepare_all_chapters
    execute_processing(chapters)

    log_completion
  end

  # Helper methods for run
  def log_start_processing
    log "Processing PDF: #{@pdf_path}"
  end

  def log_completion
    log "Done!"
  end

  def handle_runtime_error(error)
    error_exit "Error: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
  end

  def prepare_all_chapters
    chapters = extract_and_validate_chapters
    actual_depth = determine_actual_depth(chapters)
    prepare_chapters_for_processing(chapters, actual_depth)
  end

  def extract_and_validate_chapters
    chapters = extract_chapters
    error_exit "Error: No outline found in the PDF file." if chapters.nil? || chapters.empty?
    chapters
  end

  def determine_actual_depth(chapters)
    max_depth = calculate_max_depth(chapters)
    actual_depth = [@options[:depth], max_depth].min

    log_depth_adjustment(max_depth) if @options[:depth] > max_depth
    log_processing_info(actual_depth) if @options[:verbose]

    actual_depth
  end

  def calculate_max_depth(chapters)
    chapters.map { |ch| ch[:level] }.max + 1
  end

  def log_depth_adjustment(max_depth)
    log "[INFO] 指定された階層 #{@options[:depth]} はPDFの最大階層 #{max_depth} を超えています。階層 #{max_depth} で分割します。"
  end

  def log_processing_info(actual_depth)
    log "[INFO] PDFの解析を開始します..."
    log "[INFO] 階層#{actual_depth}まで分割します"
  end

  def prepare_chapters_for_processing(chapters, actual_depth)
    filtered_chapters = get_filtered_chapters(chapters, actual_depth)

    if actual_depth > 1
      combine_with_intermediate_chapters(filtered_chapters, chapters, actual_depth)
    else
      filtered_chapters
    end
  end

  def get_filtered_chapters(chapters, actual_depth)
    filtered = filter_chapters_by_depth(chapters, actual_depth)
    log_chapter_count(filtered.size, actual_depth)
    filtered
  end

  def log_chapter_count(count, depth)
    log "Found #{count} chapters at depth #{depth}"
  end

  def combine_with_intermediate_chapters(filtered_chapters, all_chapters, actual_depth)
    intermediate = get_intermediate_chapters(all_chapters, actual_depth)
    combined = merge_chapter_lists(filtered_chapters, intermediate)
    sort_chapters_hierarchically(combined)
  end

  def get_intermediate_chapters(chapters, actual_depth)
    intermediate = collect_intermediate_chapters(chapters, actual_depth)
    log "Found #{intermediate.size} intermediate level chapters"
    intermediate
  end

  def merge_chapter_lists(filtered, intermediate)
    (filtered + intermediate).uniq { |ch| [ch[:title], ch[:page]] }
  end

  def execute_processing(filtered_chapters)
    if @options[:dry_run]
      display_dry_run_info(filtered_chapters)
    else
      prepare_output_directory
      split_pdf(filtered_chapters)
    end
  end

  def parse_options
    options = default_options
    parse_command_line_options(options)
    validate_parsed_options(options)
    options
  end

  def default_options
    { verbose: false, dry_run: false, force: false, depth: 1, complete: false }
  end

  def parse_command_line_options(options)
    create_option_parser(options).parse!
  rescue OptionParser::InvalidArgument => e
    error_exit "Error: #{e.message}"
  end

  def validate_parsed_options(options)
    validate_depth_option(options[:depth])
  end

  def create_option_parser(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options] PDF_FILE"
      opts.separator ""
      opts.separator "Options:"

      opts.on("-d", "--depth LEVEL", Integer, "Split at specified depth level (default: 1)") do |d|
        options[:depth] = d
      end

      opts.on("-n", "--dry-run", "Show what would be done without doing it") do
        options[:dry_run] = true
      end

      opts.on("-f", "--force", "Remove existing chapters directory if it exists") do
        options[:force] = true
      end

      opts.on("-v", "--verbose", "Show detailed progress") do
        options[:verbose] = true
      end

      opts.on("-c", "--complete", "Include complete section content until next section starts") do
        options[:complete] = true
      end

      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
    end
  end

  def validate_depth_option(depth)
    return if depth >= 1

    warn "Error: Depth must be at least 1"
    exit 1
  end

  def validate_input!
    error_exit "Error: Please provide a PDF file path" if @pdf_path.nil? || @pdf_path.strip.empty?

    error_exit "Error: File not found: #{@pdf_path}" unless File.exist?(@pdf_path)

    return if @pdf_path.downcase.end_with?(".pdf")

    error_exit "Error: The file must be a PDF"
  end

  def build_parent_child_relationships(chapters)
    chapters.each_with_index do |chapter, idx|
      chapter[:parent_indices] = find_parent_indices(chapters, idx, chapter[:level])
      chapter[:original_index] = idx
    end
  end

  def find_parent_indices(chapters, current_idx, current_level)
    parent_indices = []

    (0...current_idx).reverse_each do |i|
      next unless chapters[i][:level] < current_level

      parent_indices << i
      current_level = chapters[i][:level] # Update current level to find parent of parent
      break if chapters[i][:level].zero?
    end

    parent_indices
  end

  def select_chapters_at_depth(chapters, depth)
    filtered = []
    chapters_with_children = identify_chapters_with_target_depth_children(chapters, depth)

    chapters.each_with_index do |chapter, idx|
      filtered << chapter if should_include_chapter?(chapter, idx, depth, chapters_with_children)
    end

    filtered.sort_by { |ch| ch[:original_index] }
  end

  def identify_chapters_with_target_depth_children(chapters, depth)
    chapters_with_children = {}

    chapters.each_with_index do |chapter, idx|
      next unless chapter[:level] < depth - 1

      # Check if the chapter has any children (not just at target depth)
      chapters_with_children[idx] = any_children?(chapters, idx)
    end

    chapters_with_children
  end

  def children_at_depth?(chapters, parent_idx, target_depth)
    chapters.any? do |ch|
      ch[:parent_indices]&.include?(parent_idx) && ch[:level] == target_depth
    end
  end

  def any_children?(chapters, parent_idx)
    chapters.any? do |ch|
      ch[:parent_indices]&.include?(parent_idx)
    end
  end

  def should_include_chapter?(chapter, idx, depth, chapters_with_children)
    # Include chapters at the target depth level
    return true if chapter[:level] == depth - 1

    # Include chapters below the target depth that don't have children
    # This ensures chapters like 9.2, 9.3, etc. are included when using depth=4
    chapter[:level] < depth - 1 && !chapters_with_children[idx]
  end

  def collect_intermediate_chapters(chapters, target_depth)
    return [] if target_depth <= 1

    intermediate = []

    # Collect all chapters from level 1 to target_depth-2 that have children
    chapters.each_with_index do |chapter, idx|
      next unless chapter[:level] < target_depth - 1
      next unless any_children?(chapters, idx)

      intermediate << chapter.dup
    end

    intermediate
  end

  def sort_chapters_hierarchically(chapters)
    # Sort by page first, then by hierarchy and appearance order
    chapters.sort do |a, b|
      page_a = a[:page] || 0
      page_b = b[:page] || 0

      if page_a == page_b
        # If on same page, use the original outline order
        # This preserves the logical structure (e.g., 24.1.1 before 24.2)
        (a[:original_index] || 0) <=> (b[:original_index] || 0)
      else
        # Otherwise, sort by page number
        page_a <=> page_b
      end
    end
  end

  def extract_chapters_from_reader(reader)
    outline_root = find_outline_root(reader)
    return nil unless outline_root

    chapters = []
    parse_outline_item(reader, outline_root[:First], chapters, 0)
    chapters
  end

  def find_outline_root(reader)
    catalog = reader.objects.trailer[:Root]
    return nil unless catalog

    catalog_obj = reader.objects[catalog]
    return nil unless catalog_obj && catalog_obj[:Outlines]

    outline_root = reader.objects[catalog_obj[:Outlines]]
    return nil unless outline_root && outline_root[:First]

    outline_root
  end

  def parse_outline_item(reader, item_ref, chapters, level)
    return unless item_ref

    item = reader.objects[item_ref]
    return unless item

    add_chapter_from_item(reader, item, chapters, level)
    process_child_items(reader, item, chapters, level)
    process_sibling_items(reader, item, chapters, level)
  end

  def add_chapter_from_item(reader, item, chapters, level)
    title = decode_pdf_string(item[:Title])
    return unless title

    chapter = create_chapter_entry(reader, item, title, level)
    chapters << chapter
    log_chapter_extraction(chapter, level) if @options[:verbose]
  end

  def create_chapter_entry(reader, item, title, level)
    {
      title: title,
      page: extract_page_number(reader, item),
      level: level
    }
  end

  def log_chapter_extraction(chapter, level)
    log ("  " * level) + "- #{chapter[:title]} (page #{chapter[:page] || 'unknown'})"
  end

  def process_child_items(reader, item, chapters, level)
    return unless item[:First]

    parse_outline_item(reader, item[:First], chapters, level + 1)
  end

  def process_sibling_items(reader, item, chapters, level)
    return unless item[:Next]

    parse_outline_item(reader, item[:Next], chapters, level)
  end

  def decode_pdf_string(str)
    return nil unless str.is_a?(String)

    decoded = decode_string_encoding(str)
    clean_decoded_string(decoded)
  end

  def decode_string_encoding(str)
    if utf16be_encoded?(str)
      decode_utf16be(str)
    else
      decode_utf8(str)
    end
  end

  def utf16be_encoded?(str)
    str.bytes.first(2) == [254, 255] || str.include?("\x00")
  end

  def decode_utf16be(str)
    str.force_encoding("UTF-16BE").encode("UTF-8")
  rescue StandardError
    decode_utf8(str)
  end

  def decode_utf8(str)
    str.force_encoding("UTF-8")
    str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  end

  def clean_decoded_string(str)
    str = str.delete_prefix("\uFEFF") # BOM削除
    str = str.tr("　", " ") # 全角スペースを半角に
    # 改行文字をスペースに置換（複数の改行は1つのスペースに）
    str = str.gsub(/[\r\n]+/, " ")
    str.strip
  end

  def extract_page_number(reader, item)
    dest = get_destination(reader, item)
    return nil unless dest

    dest = reader.objects[dest] if dest.is_a?(PDF::Reader::Reference)

    case dest
    when Array
      extract_page_from_array_dest(reader, dest)
    when String
      extract_page_from_string_dest(dest)
    end
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::InvalidObjectError
    # Handle specific PDF parsing errors
    nil
  rescue NoMethodError => e
    # Handle cases where PDF structure is unexpected
    return nil if e.message.include?("objects") || e.message.include?("[]")

    raise # Re-raise if it's an unexpected NoMethodError
  end

  def get_destination(reader, item)
    # Try direct Dest first
    return item[:Dest] if item[:Dest]

    # If no direct Dest, check for Action
    return nil unless item[:A]

    action = item[:A]
    # Resolve Action reference if needed
    action = reader.objects[action] if action.is_a?(PDF::Reader::Reference)
    # Get Dest from Action
    action.is_a?(Hash) ? action[:D] : nil
  end

  def extract_page_from_array_dest(reader, dest)
    return nil if dest.empty?

    page_ref = dest.first

    # Find the page number
    reader.pages.each_with_index do |page, index|
      if page_ref.is_a?(PDF::Reader::Reference) && (page.page_object.hash == reader.objects[page_ref].hash)
        return index + 1
      end
    end

    nil
  end

  def extract_page_from_string_dest(dest)
    # Handle named destinations (e.g., "p35")
    return ::Regexp.last_match(1).to_i if dest =~ /^p(\d+)$/

    # For complex named destinations, would need to resolve through Names dictionary
    nil
  end

  def display_dry_run_info(chapters)
    display_dry_run_header

    dry_run_context = create_dry_run_context(chapters)
    display_all_files_info(dry_run_context)

    display_total_files_count(dry_run_context)
  end

  def create_dry_run_context(chapters)
    total_pages = pdf_page_count
    all_chapters = extract_chapters

    {
      total_pages: total_pages,
      all_chapters: all_chapters,
      sorted_chapters: chapters
    }
  end

  def pdf_page_count
    PDF::Reader.new(@pdf_path).page_count
  end

  def display_all_files_info(context)
    display_front_matter_info(context[:sorted_chapters])
    display_chapters_info(context[:sorted_chapters], context[:all_chapters], context[:total_pages])
    display_appendix_info(context[:sorted_chapters], context[:all_chapters], context[:total_pages])
  end

  def calculate_extra_files_count(context)
    count = 0
    count += 1 if front_matter?(context[:sorted_chapters])
    count += 1 if appendix?(context[:sorted_chapters], context[:all_chapters], context[:total_pages])
    count
  end

  def display_total_files_count(context)
    total_count = context[:sorted_chapters].size + calculate_extra_files_count(context)
    puts "\nTotal files to create: #{total_count}"
  end

  def front_matter?(sorted_chapters)
    first_page = sorted_chapters.empty? ? 1 : (sorted_chapters.first[:page] || 1)
    first_page > 1
  end

  def appendix?(sorted_chapters, all_chapters, total_pages)
    return false if sorted_chapters.empty?

    last_chapter_end = find_chapter_end_page(sorted_chapters.last, all_chapters, total_pages)
    last_chapter_end < total_pages
  end

  def display_dry_run_header
    puts "\n=== Dry Run Mode ==="
    puts "The following files would be created in '#{output_dir}/#{CHAPTERS_DIR}/':"
    puts "Split depth: #{@options[:depth]}"
    puts "Complete sections: #{@options[:complete] ? 'enabled (--complete)' : 'disabled'}" if @options[:complete]
    puts
  end

  def display_front_matter_info(sorted_chapters)
    first_page = sorted_chapters.empty? ? 1 : (sorted_chapters.first[:page] || 1)
    return unless first_page > 1

    filename = "000_前付け.pdf"
    pages = "1-#{first_page - 1}"
    puts "  #{filename} (pages #{pages})"
  end

  def display_chapters_info(sorted_chapters, all_chapters, total_pages)
    sorted_chapters.each_with_index do |chapter, index|
      display_single_chapter_info(chapter, index, all_chapters, total_pages)
    end
  end

  def display_single_chapter_info(chapter, index, all_chapters, total_pages)
    display_chapter_line(chapter, index, all_chapters, total_pages)
    display_verbose_warnings(chapter, all_chapters) if @options[:verbose]
  end

  def display_chapter_line(chapter, index, all_chapters, total_pages)
    start_page = chapter[:page] || 1
    end_page = find_chapter_end_page(chapter, all_chapters, total_pages)
    filename = format_chapter_filename_for_display(chapter, index, all_chapters)

    puts "  #{filename} (pages #{start_page}-#{end_page})"
  end

  def format_chapter_filename_for_display(chapter, index, all_chapters)
    if @options[:depth] > 1 && chapter[:parent_indices] && !chapter[:parent_indices].empty?
      parent_idx = chapter[:parent_indices].last
      parent_title = all_chapters[parent_idx][:title] if parent_idx
      format_chapter_filename_with_parent(index + 1, chapter[:title], parent_title)
    else
      format_chapter_filename(index + 1, chapter[:title])
    end
  end

  def display_verbose_warnings(chapter, all_chapters)
    check_same_page_start(chapter, all_chapters)
    check_missing_subsections(chapter)
  end

  def check_same_page_start(chapter, all_chapters)
    return unless chapter[:parent_indices] && !chapter[:parent_indices].empty?

    parent_idx = chapter[:parent_indices].last
    parent = all_chapters[parent_idx]
    return unless parent[:page] == chapter[:page]

    puts "    [INFO] #{parent[:title]}と#{chapter[:title]}が同じページ（#{chapter[:page]}）から開始しています"
  end

  def check_missing_subsections(chapter)
    return unless chapter[:level] < @options[:depth] - 1

    puts "    [INFO] #{chapter[:title]}にはレベル#{@options[:depth]}のサブセクションがありません。章全体を出力します"
  end

  def display_appendix_info(sorted_chapters, all_chapters, total_pages)
    return if sorted_chapters.empty?

    last_sorted_chapter = sorted_chapters.max_by { |ch| ch[:page] || 0 }
    last_page = find_chapter_end_page(last_sorted_chapter, all_chapters, total_pages)

    return unless last_page < total_pages

    filename = "999_付録.pdf"
    pages = "#{last_page + 1}-#{total_pages}"
    puts "  #{filename} (pages #{pages})"
  end

  def prepare_output_directory
    output_path = File.join(output_dir, CHAPTERS_DIR)

    if Dir.exist?(output_path)
      if @options[:force]
        log "Removing existing #{CHAPTERS_DIR} directory..."
        FileUtils.rm_rf(output_path)
      else
        error_exit "Error: #{CHAPTERS_DIR} directory already exists. Use --force to overwrite."
      end
    end

    log "Creating #{CHAPTERS_DIR} directory..."
    FileUtils.mkdir_p(output_path)
  end

  def create_split_context(doc, chapters)
    {
      total_pages: doc.pages.count,
      all_chapters: extract_chapters,
      sorted_chapters: chapters
    }
  end

  def process_all_pdf_sections(doc, context)
    process_front_matter(doc, context[:sorted_chapters])
    process_chapters(doc, context[:sorted_chapters], context[:all_chapters], context[:total_pages])
    process_appendix(doc, context[:sorted_chapters], context[:all_chapters], context[:total_pages])
  end

  def process_front_matter(doc, sorted_chapters)
    first_page = sorted_chapters.empty? ? 1 : (sorted_chapters.first[:page] || 1)
    return unless first_page > 1

    log "Extracting front matter..." if @options[:verbose]
    extract_pages(doc, 1, first_page - 1, "000_前付け.pdf")
  end

  def process_chapters(doc, sorted_chapters, all_chapters, total_pages)
    sorted_chapters.each_with_index do |chapter, index|
      process_single_chapter(doc, chapter, index, all_chapters, total_pages)
    end
  end

  def process_single_chapter(doc, chapter, index, all_chapters, total_pages)
    start_page = chapter[:page] || 1
    end_page = find_chapter_end_page(chapter, all_chapters, total_pages)
    filename = build_chapter_filename(chapter, index, all_chapters)

    log "Extracting: #{chapter[:title]} (pages #{start_page}-#{end_page})..." if @options[:verbose]
    extract_pages(doc, start_page, end_page, filename)
  end

  def build_chapter_filename(chapter, index, all_chapters)
    if @options[:depth] > 1 && chapter[:parent_indices] && !chapter[:parent_indices].empty?
      parent_idx = chapter[:parent_indices].last
      parent_title = all_chapters[parent_idx][:title] if parent_idx
      format_chapter_filename_with_parent(index + 1, chapter[:title], parent_title)
    else
      format_chapter_filename(index + 1, chapter[:title])
    end
  end

  def process_appendix(doc, sorted_chapters, all_chapters, total_pages)
    return if sorted_chapters.empty?

    last_sorted_chapter = sorted_chapters.max_by { |ch| ch[:page] || 0 }
    last_page = find_chapter_end_page(last_sorted_chapter, all_chapters, total_pages)

    return unless last_page < total_pages

    log "Extracting appendix..." if @options[:verbose]
    extract_pages(doc, last_page + 1, total_pages, "999_付録.pdf")
  end

  def find_chapter_end_page(chapter, all_chapters, total_pages)
    current_idx = get_chapter_index(chapter, all_chapters)
    return total_pages if current_idx.nil?

    calculate_end_page_for_chapter(chapter, current_idx, all_chapters, total_pages)
  end

  def calculate_end_page_for_chapter(chapter, current_idx, all_chapters, total_pages)
    next_chapter = find_next_chapter_at_same_or_higher_level(current_idx, chapter[:level], all_chapters)

    if next_chapter && next_chapter[:page]
      calculate_end_page_from_next_chapter(chapter, next_chapter)
    elsif parent?(chapter)
      find_end_page_from_parent(chapter, all_chapters, total_pages)
    else
      total_pages
    end
  end

  def calculate_end_page_from_next_chapter(chapter, next_chapter)
    if next_chapter[:page] == chapter[:page] || @options[:complete]
      next_chapter[:page]
    else
      next_chapter[:page] - 1
    end
  end

  def get_chapter_index(chapter, all_chapters)
    return chapter[:original_index] if chapter[:original_index]

    all_chapters.find_index { |ch| ch[:title] == chapter[:title] && ch[:page] == chapter[:page] }
  end

  def find_next_chapter_at_same_or_higher_level(current_idx, current_level, all_chapters)
    all_chapters.find do |ch|
      ch_idx = get_chapter_index(ch, all_chapters)
      ch_idx && ch_idx > current_idx && ch[:level] <= current_level
    end
  end

  def parent?(chapter)
    chapter[:parent_indices] && !chapter[:parent_indices].empty?
  end

  def find_end_page_from_parent(chapter, all_chapters, total_pages)
    parent_idx = chapter[:parent_indices].last
    parent = all_chapters[parent_idx]
    parent_level = parent[:level]

    parent_next = find_next_chapter_at_same_or_higher_level(parent_idx, parent_level, all_chapters)

    if parent_next && parent_next[:page]
      # If the parent's next chapter starts on the same page as the current chapter, use that page
      # Otherwise, use the page before the parent's next chapter
      if parent_next[:page] == chapter[:page]
        parent_next[:page]
      else
        parent_next[:page] - 1
      end
    else
      total_pages
    end
  end

  def extract_pages(source_doc, start_page, end_page, filename)
    output_path = build_output_path(filename)
    new_doc = create_pdf_with_pages(source_doc, start_page, end_page)

    save_pdf_document(new_doc, output_path, filename)
  end

  def build_output_path(filename)
    File.join(output_dir, CHAPTERS_DIR, filename)
  end

  def create_pdf_with_pages(source_doc, start_page, end_page)
    new_doc = HexaPDF::Document.new
    copy_pages_to_document(source_doc, new_doc, start_page, end_page)
    copy_metadata_to_document(source_doc, new_doc)
    new_doc
  end

  def copy_pages_to_document(source_doc, new_doc, start_page, end_page)
    (start_page..end_page).each do |page_num|
      page = source_doc.pages[page_num - 1]
      new_doc.pages << new_doc.import(page) if page
    end
  end

  def copy_metadata_to_document(source_doc, new_doc)
    return unless source_doc.catalog[:Info]

    new_doc.catalog[:Info] = new_doc.import(source_doc.catalog[:Info])
  end

  def save_pdf_document(doc, output_path, filename)
    doc.write(output_path)
    log "Created: #{filename}" unless @options[:verbose]
  end

  def format_chapter_filename(number, title)
    num_str = format_file_number(number)
    clean_title = sanitize_filename(title)
    build_filename(num_str, clean_title)
  end

  def format_chapter_filename_with_parent(number, title, parent_title)
    num_str = format_file_number(number)
    clean_title = sanitize_filename(title)

    if parent_title
      build_filename_with_parent(num_str, clean_title, parent_title)
    else
      build_filename(num_str, clean_title)
    end
  end

  def format_file_number(number)
    format("%03d", number)
  end

  def sanitize_filename(text)
    text.gsub(INVALID_FILENAME_CHARS, "_")
  end

  def build_filename_with_parent(num_str, clean_title, parent_title)
    clean_parent = sanitize_filename(parent_title)
    "#{num_str}_#{clean_parent}_#{clean_title}.pdf"
  end

  def build_filename(num_str, clean_title)
    "#{num_str}_#{clean_title}.pdf"
  end

  def output_dir
    File.dirname(@pdf_path)
  end

  def log(message)
    puts message unless @options[:dry_run] && !@options[:verbose]
  end

  def error_exit(message)
    warn message
    exit 1
  end
end

# Run the script if executed directly
PDFChapterSplitter.new.run if __FILE__ == $PROGRAM_NAME
