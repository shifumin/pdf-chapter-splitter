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
    log "Processing PDF: #{@pdf_path}"

    chapters = extract_chapters
    error_exit "Error: No outline found in the PDF file." if chapters.nil? || chapters.empty?

    # Validate and adjust depth
    max_depth = chapters.map { |ch| ch[:level] }.max + 1
    actual_depth = [@options[:depth], max_depth].min

    if @options[:depth] > max_depth
      log "[INFO] 指定された階層 #{@options[:depth]} はPDFの最大階層 #{max_depth} を超えています。階層 #{max_depth} で分割します。"
    end

    log "[INFO] PDFの解析を開始します..." if @options[:verbose]
    log "[INFO] 階層#{actual_depth}まで分割します" if @options[:verbose]

    # Filter chapters based on depth
    filtered_chapters = filter_chapters_by_depth(chapters, actual_depth)
    log "Found #{filtered_chapters.size} chapters at depth #{actual_depth}"

    if @options[:dry_run]
      display_dry_run_info(filtered_chapters)
    else
      prepare_output_directory
      split_pdf(filtered_chapters)
    end

    log "Done!"
  rescue StandardError => e
    error_exit "Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end

  private

  def parse_options
    options = { verbose: false, dry_run: false, force: false, depth: 1 }

    parser = OptionParser.new do |opts|
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

      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
    end

    parser.parse!

    # Validate depth option
    if options[:depth] < 1
      warn "Error: Depth must be at least 1"
      exit 1
    end

    options
  end

  def validate_input!
    error_exit "Error: Please provide a PDF file path" if @pdf_path.nil? || @pdf_path.empty?

    error_exit "Error: File not found: #{@pdf_path}" unless File.exist?(@pdf_path)

    return if @pdf_path.downcase.end_with?(".pdf")

    error_exit "Error: The file must be a PDF"
  end

  def filter_chapters_by_depth(chapters, depth)
    return [] if chapters.empty?

    filtered = []
    chapters_with_children = {}

    # Build parent-child relationships
    chapters.each_with_index do |chapter, idx|
      parent_indices = []

      # Find all parent chapters for this chapter
      (0...idx).reverse_each do |i|
        if chapters[i][:level] < chapter[:level]
          parent_indices << i
          break if chapters[i][:level].zero?
        end
      end

      chapter[:parent_indices] = parent_indices
      chapter[:original_index] = idx
    end

    # For each chapter at target depth, check if it has children
    chapters.each_with_index do |chapter, idx|
      if chapter[:level] < depth - 1
        # Check if this chapter has children at the target depth
        has_target_depth_children = chapters.any? do |ch|
          ch[:parent_indices] && ch[:parent_indices].include?(idx) && ch[:level] == depth - 1
        end
        chapters_with_children[idx] = has_target_depth_children
      elsif chapter[:level] == depth - 1
        filtered << chapter
      end
    end

    # Add chapters without target-depth children
    chapters.each_with_index do |chapter, idx|
      filtered << chapter if chapter[:level] < depth - 1 && !chapters_with_children[idx]
    end

    # Sort by original appearance order
    filtered.sort_by { |ch| ch[:original_index] }
  end

  def extract_chapters
    reader = PDF::Reader.new(@pdf_path)
    outline_root = find_outline_root(reader)

    return nil unless outline_root

    chapters = []
    parse_outline_item(reader, outline_root[:First], chapters, 0)
    chapters
  rescue PDF::Reader::MalformedPDFError => e
    error_exit "Error: Malformed PDF - #{e.message}"
  rescue StandardError => e
    error_exit "Error reading PDF: #{e.message}"
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

    # Extract title
    title = decode_pdf_string(item[:Title])

    # Extract page number
    page_num = extract_page_number(reader, item)

    if title
      chapters << {
        title: title,
        page: page_num,
        level: level
      }
      log ("  " * level) + "- #{title} (page #{page_num || 'unknown'})" if @options[:verbose]
    end

    # Process children
    parse_outline_item(reader, item[:First], chapters, level + 1) if item[:First]

    # Process siblings
    return unless item[:Next]

    parse_outline_item(reader, item[:Next], chapters, level)
  end

  def decode_pdf_string(str)
    return nil unless str.is_a?(String)

    # UTF-16BE処理
    if str.bytes.first(2) == [254, 255] || str.include?("\x00")
      begin
        str = str.force_encoding("UTF-16BE").encode("UTF-8")
      rescue StandardError
        str = str.force_encoding("UTF-8")
        str = str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      end
    else
      str = str.force_encoding("UTF-8")
      str = str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    end

    str = str.delete_prefix("\uFEFF") # BOM削除
    str = str.tr("　", " ") # 全角スペースを半角に
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
  rescue StandardError
    nil
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
    puts "\n=== Dry Run Mode ==="
    puts "The following files would be created in '#{output_dir}/#{CHAPTERS_DIR}/':"
    puts "Split depth: #{@options[:depth]}"
    puts

    reader = PDF::Reader.new(@pdf_path)
    total_pages = reader.page_count
    all_chapters = extract_chapters

    # Sort filtered chapters by page number
    sorted_chapters = chapters.sort_by { |ch| ch[:page] || 0 }

    file_count = 0

    # Check for front matter
    first_page = sorted_chapters.empty? ? 1 : (sorted_chapters.first[:page] || 1)
    if first_page > 1
      filename = "00_前付け.pdf"
      pages = "1-#{first_page - 1}"
      puts "  #{filename} (pages #{pages})"
      file_count += 1
    end

    # Process chapters
    sorted_chapters.each_with_index do |chapter, index|
      start_page = chapter[:page] || 1
      end_page = find_chapter_end_page(chapter, all_chapters, total_pages)

      # Format filename with parent context if depth > 1
      filename = if @options[:depth] > 1 && chapter[:parent_indices] && !chapter[:parent_indices].empty?
                   parent_idx = chapter[:parent_indices].last
                   parent_title = all_chapters[parent_idx][:title] if parent_idx
                   format_chapter_filename_with_parent(index + 1, chapter[:title], parent_title)
                 else
                   format_chapter_filename(index + 1, chapter[:title])
                 end

      puts "  #{filename} (pages #{start_page}-#{end_page})"

      # Verbose info for special cases
      next unless @options[:verbose]

      # Check if parent starts at same page
      if chapter[:parent_indices] && !chapter[:parent_indices].empty?
        parent_idx = chapter[:parent_indices].last
        parent = all_chapters[parent_idx]
        if parent[:page] == chapter[:page]
          puts "    [INFO] #{parent[:title]}と#{chapter[:title]}が同じページ（#{chapter[:page]}）から開始しています"
        end
      end

      # Check if chapter has no sub-sections at target depth
      if chapter[:level] < @options[:depth] - 1
        puts "    [INFO] #{chapter[:title]}にはレベル#{@options[:depth]}のサブセクションがありません。章全体を出力します"
      end
    end

    # Check for appendix
    unless sorted_chapters.empty?
      last_sorted_chapter = sorted_chapters.max_by { |ch| ch[:page] || 0 }
      last_page = find_chapter_end_page(last_sorted_chapter, all_chapters, total_pages)

      if last_page < total_pages
        filename = "99_付録.pdf"
        pages = "#{last_page + 1}-#{total_pages}"
        puts "  #{filename} (pages #{pages})"
        file_count += 1
      end
    end

    puts "\nTotal files to create: #{sorted_chapters.size + file_count}"
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

  def split_pdf(chapters)
    doc = HexaPDF::Document.open(@pdf_path)
    total_pages = doc.pages.count
    all_chapters = extract_chapters # Get all chapters for context

    # Sort filtered chapters by page number
    sorted_chapters = chapters.sort_by { |ch| ch[:page] || 0 }

    # Process front matter if exists
    first_page = sorted_chapters.empty? ? 1 : (sorted_chapters.first[:page] || 1)
    if first_page > 1
      log "Extracting front matter..." if @options[:verbose]
      extract_pages(doc, 1, first_page - 1, "00_前付け.pdf")
    end

    # Process each chapter
    sorted_chapters.each_with_index do |chapter, index|
      start_page = chapter[:page] || 1

      # Find end page based on all chapters
      end_page = find_chapter_end_page(chapter, all_chapters, total_pages)

      # Format filename with parent context if depth > 1
      filename = if @options[:depth] > 1 && chapter[:parent_indices] && !chapter[:parent_indices].empty?
                   parent_idx = chapter[:parent_indices].last
                   parent_title = all_chapters[parent_idx][:title] if parent_idx
                   format_chapter_filename_with_parent(index + 1, chapter[:title], parent_title)
                 else
                   format_chapter_filename(index + 1, chapter[:title])
                 end

      log "Extracting: #{chapter[:title]} (pages #{start_page}-#{end_page})..." if @options[:verbose]
      extract_pages(doc, start_page, end_page, filename)
    end

    # Process appendix if exists
    return if sorted_chapters.empty?

    last_sorted_chapter = sorted_chapters.max_by { |ch| ch[:page] || 0 }
    last_page = find_chapter_end_page(last_sorted_chapter, all_chapters, total_pages)

    return unless last_page < total_pages

    log "Extracting appendix..." if @options[:verbose]
    extract_pages(doc, last_page + 1, total_pages, "99_付録.pdf")
  end

  def find_chapter_end_page(chapter, all_chapters, total_pages)
    current_idx = chapter[:original_index]

    # If original_index is not set, fall back to finding by title and page
    if current_idx.nil?
      current_idx = all_chapters.find_index { |ch| ch[:title] == chapter[:title] && ch[:page] == chapter[:page] }
      return total_pages if current_idx.nil?
    end

    # Find the next chapter at the same or higher level
    next_chapter = all_chapters.find do |ch|
      ch_idx = ch[:original_index] || all_chapters.find_index { |c| c[:title] == ch[:title] && c[:page] == ch[:page] }
      ch_idx && ch_idx > current_idx && ch[:level] <= chapter[:level]
    end

    if next_chapter && next_chapter[:page]
      next_chapter[:page] - 1
    elsif chapter[:parent_indices] && !chapter[:parent_indices].empty?
      # If no next chapter at same/higher level, check for parent's next sibling
      parent_idx = chapter[:parent_indices].last
      parent_next = all_chapters.find do |ch|
        ch_idx = ch[:original_index] || all_chapters.find_index { |c| c[:title] == ch[:title] && c[:page] == ch[:page] }
        ch_idx && ch_idx > parent_idx && ch[:level] <= all_chapters[parent_idx][:level]
      end

      if parent_next && parent_next[:page]
        parent_next[:page] - 1
      else
        total_pages
      end
    else
      total_pages
    end
  end

  def extract_pages(source_doc, start_page, end_page, filename)
    output_path = File.join(output_dir, CHAPTERS_DIR, filename)

    new_doc = HexaPDF::Document.new

    # Copy pages (1-indexed to 0-indexed)
    (start_page..end_page).each do |page_num|
      page = source_doc.pages[page_num - 1]
      new_doc.pages << new_doc.import(page) if page
    end

    # Copy metadata
    new_doc.catalog[:Info] = new_doc.import(source_doc.catalog[:Info]) if source_doc.catalog[:Info]

    # Save the new PDF
    new_doc.write(output_path)
    log "Created: #{filename}" unless @options[:verbose]
  end

  def format_chapter_filename(number, title)
    # Format number with zero padding
    num_str = format("%02d", number)

    # Clean title for filename
    clean_title = title.gsub(INVALID_FILENAME_CHARS, "_")

    "#{num_str}_#{clean_title}.pdf"
  end

  def format_chapter_filename_with_parent(number, title, parent_title)
    # Format number with zero padding
    num_str = format("%02d", number)

    # Clean titles for filename
    clean_parent = parent_title ? parent_title.gsub(INVALID_FILENAME_CHARS, "_") : ""
    clean_title = title.gsub(INVALID_FILENAME_CHARS, "_")

    if parent_title
      "#{num_str}_#{clean_parent}_#{clean_title}.pdf"
    else
      "#{num_str}_#{clean_title}.pdf"
    end
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
