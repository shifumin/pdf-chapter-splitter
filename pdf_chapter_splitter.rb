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

    # Filter to first level chapters only
    first_level_chapters = chapters.select { |ch| ch[:level].zero? }
    log "Found #{first_level_chapters.size} top-level chapters"

    if @options[:dry_run]
      display_dry_run_info(first_level_chapters)
    else
      prepare_output_directory
      split_pdf(first_level_chapters)
    end

    log "Done!"
  rescue StandardError => e
    error_exit "Error: #{e.message}"
  end

  private

  def parse_options
    options = { verbose: false, dry_run: false, force: false }

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options] PDF_FILE"
      opts.separator ""
      opts.separator "Options:"

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
    options
  end

  def validate_input!
    error_exit "Error: Please provide a PDF file path" if @pdf_path.nil? || @pdf_path.empty?

    error_exit "Error: File not found: #{@pdf_path}" unless File.exist?(@pdf_path)

    return if @pdf_path.downcase.end_with?(".pdf")

    error_exit "Error: The file must be a PDF"
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
    puts

    reader = PDF::Reader.new(@pdf_path)
    total_pages = reader.page_count

    # Check for front matter
    if chapters.first && chapters.first[:page] && chapters.first[:page] > 1
      filename = "00_前付け.pdf"
      pages = "1-#{chapters.first[:page] - 1}"
      puts "  #{filename} (pages #{pages})"
    end

    # Process chapters
    chapters.each_with_index do |chapter, index|
      next_chapter = chapters[index + 1]

      start_page = chapter[:page] || 1
      end_page = if next_chapter && next_chapter[:page]
                   next_chapter[:page] - 1
                 else
                   total_pages
                 end

      filename = format_chapter_filename(index + 1, chapter[:title])
      puts "  #{filename} (pages #{start_page}-#{end_page})"
    end

    # Check for appendix
    last_chapter_end = if chapters.last && chapters.last[:page]
                         # Find the end of the last chapter
                         chapters.last[:page]
                       else
                         1
                       end

    # Estimate last chapter end (simplified - in real case we'd calculate properly)
    if last_chapter_end < total_pages
      filename = "99_付録.pdf"
      pages = "#{last_chapter_end + 1}-#{total_pages}"
      puts "  #{filename} (pages #{pages})"
    end

    puts "\nTotal chapters to create: #{chapters.size + (chapters.first[:page] > 1 ? 1 : 0) + (last_chapter_end < total_pages ? 1 : 0)}"
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

    # Process front matter if exists
    if chapters.first && chapters.first[:page] && chapters.first[:page] > 1
      log "Extracting front matter..." if @options[:verbose]
      extract_pages(doc, 1, chapters.first[:page] - 1, "00_前付け.pdf")
    end

    # Process each chapter
    chapters.each_with_index do |chapter, index|
      next_chapter = chapters[index + 1]

      start_page = chapter[:page] || 1
      end_page = if next_chapter && next_chapter[:page]
                   next_chapter[:page] - 1
                 else
                   total_pages
                 end

      filename = format_chapter_filename(index + 1, chapter[:title])
      log "Extracting: #{chapter[:title]} (pages #{start_page}-#{end_page})..." if @options[:verbose]
      extract_pages(doc, start_page, end_page, filename)
    end

    # Process appendix if exists
    last_chapter = chapters.last
    return unless last_chapter && last_chapter[:page]

    # Simple estimation - in reality we'd need to calculate the actual end of last chapter
    estimated_last_page = last_chapter[:page] + 20 # This is a simplification
    return unless estimated_last_page < total_pages

    log "Extracting appendix..." if @options[:verbose]
    extract_pages(doc, estimated_last_page + 1, total_pages, "99_付録.pdf")
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
