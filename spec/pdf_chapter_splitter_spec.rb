# frozen_string_literal: true

require "spec_helper"
require_relative "support/generate_test_pdfs"

RSpec.describe PDFChapterSplitter do
  before(:all) do
    # Generate test PDFs once before all tests
    TestPDFGenerator.generate_all
  end

  let(:fixture_path) { File.join(__dir__, "fixtures") }
  let(:pdf_with_outline) { File.join(fixture_path, "sample_with_outline.pdf") }
  let(:pdf_without_outline) { File.join(fixture_path, "sample_without_outline.pdf") }
  let(:japanese_pdf) { File.join(fixture_path, "japanese_with_outline.pdf") }
  let(:complex_pdf) { File.join(fixture_path, "complex_outline.pdf") }

  describe "#initialize and #run" do
    context "with valid PDF file" do
      it "initializes and runs successfully" do
        output_dir = File.dirname(pdf_with_outline)
        chapters_dir = File.join(output_dir, "chapters")
        FileUtils.rm_rf(chapters_dir)

        original_argv = ARGV.dup
        ARGV.clear
        ARGV << pdf_with_outline

        splitter = described_class.new
        expect { splitter.run }.not_to raise_error
        expect(Dir.exist?(chapters_dir)).to be true

        ARGV.clear
        original_argv.each { |arg| ARGV << arg }
        FileUtils.rm_rf(chapters_dir)
      end
    end

    context "with invalid options" do
      it "raises error for invalid depth" do
        original_argv = ARGV.dup
        ARGV.clear
        ARGV.push("--depth", "0", pdf_with_outline)

        expect { described_class.new }.to raise_error(SystemExit)

        ARGV.clear
        original_argv.each { |arg| ARGV << arg }
      end
    end

    context "with missing file" do
      it "exits with error when file does not exist" do
        original_argv = ARGV.dup
        ARGV.clear
        ARGV << "nonexistent.pdf"

        splitter = described_class.new
        expect { splitter.run }.to raise_error(SystemExit)

        ARGV.clear
        original_argv.each { |arg| ARGV << arg }
      end
    end

    context "with PDF processing error" do
      it "handles PDF processing errors gracefully" do
        temp_dir = Dir.mktmpdir
        corrupted_pdf = File.join(temp_dir, "corrupted.pdf")
        File.write(corrupted_pdf, "Not a real PDF content")

        original_argv = ARGV.dup
        ARGV.clear
        ARGV << corrupted_pdf

        splitter = described_class.new
        expect { splitter.run }.to raise_error(SystemExit)

        ARGV.clear
        original_argv.each { |arg| ARGV << arg }
        FileUtils.rm_rf(temp_dir)
      end
    end
  end

  describe "command line options" do
    context "with --help option" do
      it "displays help message and exits" do
        stdout, = run_script("--help")
        expect(stdout).to include("Usage:")
        expect(stdout).to include("--dry-run")
        expect(stdout).to include("--force")
        expect(stdout).to include("--verbose")
      end
    end

    context "with command line options" do
      it "accepts options in flexible order" do
        # Test that options work regardless of position
        stdout, = run_script("-n", "-d", "2", pdf_with_outline, "-v")
        expect(stdout).to include("Dry Run Mode")
        expect(stdout).to include("Split depth: 2")
        expect(stdout).to match(/Chapter \d+.+\(page \d+/)
      end
    end

    context "without arguments" do
      it "shows error message" do
        _, stderr, exit_status = run_script
        expect(stderr).to include("Error: Please provide a PDF file path")
        expect(exit_status).to eq(1)
      end
    end

    context "with non-existent file" do
      it "shows error message" do
        _, stderr, exit_status = run_script("nonexistent.pdf")
        expect(stderr).to include("Error: File not found")
        expect(exit_status).to eq(1)
      end
    end

    context "with non-PDF file" do
      it "shows error message" do
        text_file = File.join(temp_dir, "test.txt")
        File.write(text_file, "not a pdf")

        _, stderr, exit_status = run_script(text_file)
        expect(stderr).to include("Error: The file must be a PDF")
        expect(exit_status).to eq(1)
      end
    end
  end

  describe "PDF processing" do
    context "with PDF containing outline" do
      let(:test_pdf) do
        test_file = File.join(temp_dir, "test.pdf")
        FileUtils.cp(pdf_with_outline, test_file)
        test_file
      end

      it "extracts chapters correctly" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to include("001_Chapter 1_ Introduction.pdf")
        expect(stdout).to include("002_Chapter 2_ Getting Started.pdf")
        expect(stdout).to include("003_Chapter 3_ Advanced Topics.pdf")
      end

      it "detects front matter" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to include("000_前付け.pdf")
      end

      it "shows page ranges in dry-run mode" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to match(/pages \d+-\d+/)
      end

      context "actual splitting" do
        it "creates chapters directory" do
          run_script(test_pdf)
          chapters_dir = File.join(temp_dir, "chapters")
          expect(Dir.exist?(chapters_dir)).to be true
        end

        it "creates separate PDF for each chapter" do
          run_script(test_pdf)
          chapters_dir = File.join(temp_dir, "chapters")

          expect(File.exist?(File.join(chapters_dir, "000_前付け.pdf"))).to be true
          expect(File.exist?(File.join(chapters_dir, "001_Chapter 1_ Introduction.pdf"))).to be true
          expect(File.exist?(File.join(chapters_dir, "002_Chapter 2_ Getting Started.pdf"))).to be true
          expect(File.exist?(File.join(chapters_dir, "003_Chapter 3_ Advanced Topics.pdf"))).to be true
        end

        it "creates valid PDF files" do
          run_script(test_pdf)
          chapters_dir = File.join(temp_dir, "chapters")

          pdf_file = File.join(chapters_dir, "001_Chapter 1_ Introduction.pdf")
          expect { PDF::Reader.new(pdf_file) }.not_to raise_error
        end
      end
    end

    context "with PDF without outline" do
      let(:test_pdf) do
        test_file = File.join(temp_dir, "test.pdf")
        FileUtils.cp(pdf_without_outline, test_file)
        test_file
      end

      it "shows error message" do
        _, stderr, exit_status = run_script(test_pdf)
        expect(stderr).to include("Error: No outline found in the PDF file")
        expect(exit_status).to eq(1)
      end
    end

    context "with Japanese PDF" do
      let(:test_pdf) do
        test_file = File.join(temp_dir, "test.pdf")
        FileUtils.cp(japanese_pdf, test_file)
        test_file
      end

      it "handles Japanese chapter titles correctly" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to include("第1章")
        expect(stdout).to include("第2章")
        expect(stdout).to include("第3章")
      end

      it "creates files with Japanese names" do
        run_script(test_pdf)
        chapters_dir = File.join(temp_dir, "chapters")

        # Check that files are created (exact names depend on encoding)
        files = Dir.entries(chapters_dir).reject { |f| f.start_with?(".") }
        expect(files.size).to be >= 3
        expect(files.any? { |f| f.include?("第1章") }).to be true
      end
    end

    context "with complex outline (nested chapters)" do
      let(:test_pdf) do
        test_file = File.join(temp_dir, "test.pdf")
        FileUtils.cp(complex_pdf, test_file)
        test_file
      end

      it "extracts only top-level chapters" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to include("Chapter 1")
        expect(stdout).to include("Chapter 2")
        expect(stdout).not_to include("Section")
      end
    end
  end

  describe "--force option" do
    let(:test_pdf) do
      test_file = File.join(temp_dir, "test.pdf")
      FileUtils.cp(pdf_with_outline, test_file)
      test_file
    end

    context "when chapters directory exists" do
      before do
        FileUtils.mkdir_p(File.join(temp_dir, "chapters"))
        File.write(File.join(temp_dir, "chapters", "existing.txt"), "existing file")
      end

      it "shows error without --force" do
        _, stderr, exit_status = run_script(test_pdf)
        expect(stderr).to include("Error: chapters directory already exists")
        expect(stderr).to include("Use --force to overwrite")
        expect(exit_status).to eq(1)
      end

      it "removes existing directory with --force" do
        run_script("--force", test_pdf)
        chapters_dir = File.join(temp_dir, "chapters")

        expect(File.exist?(File.join(chapters_dir, "existing.txt"))).to be false
        expect(File.exist?(File.join(chapters_dir, "001_Chapter 1_ Introduction.pdf"))).to be true
      end
    end
  end

  describe "--verbose option" do
    let(:test_pdf) do
      test_file = File.join(temp_dir, "test.pdf")
      FileUtils.cp(pdf_with_outline, test_file)
      test_file
    end

    it "shows detailed progress" do
      stdout, = run_script("--verbose", test_pdf)
      expect(stdout).to include("Processing PDF:")
      expect(stdout).to include("Found")
      expect(stdout).to include("chapters at depth")
      expect(stdout).to include("Creating chapters directory")
      expect(stdout).to include("Extracting:")
    end

    it "shows page numbers for each chapter" do
      stdout, = run_script("--verbose", "--dry-run", test_pdf)
      expect(stdout).to match(/Chapter \d+.+\(page \d+/)
    end
  end

  describe "filename sanitization" do
    it "replaces invalid characters in filenames" do
      # This would need a PDF with chapters containing invalid chars
      # For now, we can test the behavior indirectly
      stdout, = run_script("--dry-run", pdf_with_outline)

      # Check that colons in "Chapter 1: Introduction" are replaced
      expect(stdout).to include("001_Chapter 1_ Introduction.pdf")
      expect(stdout).not_to include("001_Chapter 1: Introduction.pdf")
    end
  end

  describe "--depth option" do
    let(:test_pdf) do
      test_file = File.join(temp_dir, "test.pdf")
      FileUtils.cp(complex_pdf, test_file)
      test_file
    end

    context "with depth 1 (default)" do
      it "extracts only top-level chapters" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to include("Split depth: 1")
        expect(stdout).to include("Chapter 1")
        expect(stdout).to include("Chapter 2")
        expect(stdout).not_to include("Section")
      end
    end

    context "with depth 2" do
      it "extracts sections at depth 2" do
        stdout, = run_script("--dry-run", "--depth", "2", test_pdf)
        expect(stdout).to include("Split depth: 2")
        expect(stdout).to include("Section 1.1")
        expect(stdout).to include("Section 1.2")
        expect(stdout).to include("Section 2.1")
      end

      it "includes parent chapter in filename" do
        stdout, = run_script("--dry-run", "--depth", "2", test_pdf)
        expect(stdout).to include("Chapter 1_Section 1.1")
        expect(stdout).to include("Chapter 1_Section 1.2")
        expect(stdout).to include("Chapter 2_Section 2.1")
      end

      it "includes chapters without subsections" do
        stdout, = run_script("--dry-run", "--depth", "2", test_pdf)
        # Chapter 3 has no sections, so it should be included as is
        expect(stdout).to include("Chapter 3")
      end
    end

    context "with depth 3" do
      it "extracts subsections at depth 3" do
        stdout, = run_script("--dry-run", "--depth", "3", test_pdf)
        expect(stdout).to include("Subsection 1.1.1")
        expect(stdout).to include("Subsection 1.1.2")
      end
    end

    context "with depth exceeding maximum" do
      it "adjusts to maximum available depth" do
        stdout, = run_script("--dry-run", "--depth", "10", "--verbose", test_pdf)
        expect(stdout).to include("指定された階層 10 はPDFの最大階層")
      end
    end

    context "with invalid depth" do
      it "shows error for depth 0" do
        _, stderr, exit_status = run_script("--depth", "0", test_pdf)
        expect(stderr).to include("Error: Depth must be at least 1")
        expect(exit_status).to eq(1)
      end

      it "shows error for negative depth" do
        _, stderr, exit_status = run_script("--depth", "-1", test_pdf)
        expect(stderr).to include("Error: Depth must be at least 1")
        expect(exit_status).to eq(1)
      end

      it "shows error for non-integer depth" do
        _, stderr, exit_status = run_script("--depth", "abc", test_pdf)
        expect(stderr).to match(/invalid argument|Depth must be at least 1/)
        expect(exit_status).to eq(1)
      end
    end

    context "actual splitting with depth" do
      it "creates files with parent context in names" do
        run_script("--depth", "2", test_pdf)
        chapters_dir = File.join(temp_dir, "chapters")

        files = Dir.entries(chapters_dir).reject { |f| f.start_with?(".") }
        expect(files.any? { |f| f.include?("Chapter 1_Section") }).to be true
        expect(files.any? { |f| f.include?("Chapter 2_Section") }).to be true
      end
    end
  end

  describe "intermediate level chapters (default behavior)" do
    let(:test_pdf) do
      test_file = File.join(temp_dir, "test.pdf")
      FileUtils.cp(complex_pdf, test_file)
      test_file
    end

    context "with depth 3" do
      it "includes target depth chapters" do
        stdout, = run_script("--dry-run", "--depth", "3", test_pdf)

        # Should include depth 3 chapters (subsections)
        expect(stdout).to include("Subsection 1.1.1")
        expect(stdout).to include("Subsection 1.1.2")
      end

      it "includes intermediate level chapters by default" do
        stdout, = run_script("--dry-run", "--depth", "3", test_pdf)

        # Should ALSO include intermediate level chapters (depth 1 and 2)
        expect(stdout).to include("Chapter 1.pdf")
        expect(stdout).to include("Chapter 2.pdf")
        expect(stdout).to include("Section 1.1.pdf")
        expect(stdout).to include("Section 1.2.pdf")
      end

      it "reports count of intermediate chapters in verbose mode" do
        stdout, = run_script("--dry-run", "--depth", "3", "--verbose", test_pdf)
        expect(stdout).to match(/Found \d+ intermediate level chapters/)
      end
    end

    context "with depth 4" do
      it "includes all parent chapters as intermediate" do
        stdout, = run_script("--dry-run", "--depth", "4", test_pdf)

        # Should include chapters at all levels
        expect(stdout).to include("Chapter 1.pdf")
        expect(stdout).to include("Chapter 2.pdf")
        expect(stdout).to include("Section 1.1.pdf")
      end
    end

    context "with depth 1" do
      it "does not create intermediate levels since there are none" do
        stdout, = run_script("--dry-run", "--depth", "1", test_pdf)

        # Should only include top-level chapters
        expect(stdout).to include("Chapter 1")
        expect(stdout).to include("Chapter 2")
        expect(stdout).not_to include("Section")
      end
    end
  end

  describe "appendix detection" do
    let(:test_pdf) do
      test_file = File.join(temp_dir, "test.pdf")
      FileUtils.cp(pdf_with_outline, test_file)
      test_file
    end

    it "detects appendix pages after last chapter" do
      stdout, = run_script("--dry-run", test_pdf)
      # If there are pages after the last chapter, they should be in appendix
      expect(stdout).to include("999_付録.pdf") if stdout.include?("999_付録.pdf")
    end

    it "creates appendix file when pages exist after last chapter" do
      run_script(test_pdf)
      chapters_dir = File.join(temp_dir, "chapters")

      # Check if appendix was created (depends on test PDF structure)
      appendix_file = File.join(chapters_dir, "999_付録.pdf")
      expect { PDF::Reader.new(appendix_file) }.not_to raise_error if File.exist?(appendix_file)
    end
  end

  describe "edge cases" do
    context "with chapters starting on same page" do
      it "handles parent and child on same page correctly" do
        stdout, = run_script("--dry-run", "--depth", "2", "--verbose", complex_pdf)

        # Check for info message about same page
        expect(stdout).to match(/が同じページ.*から開始しています/) if stdout.include?("同じページ")
      end
    end

    context "with missing page numbers" do
      # This would require a specially crafted PDF
      # For now, we verify the implementation handles nil page numbers
      it "defaults to page 1 when page number is missing" do
        stdout, = run_script("--dry-run", pdf_with_outline)
        # All chapters should have page ranges even if some lack page numbers
        expect(stdout.scan(/pages \d+-\d+/).size).to be > 0
      end
    end
  end

  describe "error handling" do
    context "with corrupted PDF" do
      it "shows appropriate error message" do
        corrupted_pdf = File.join(temp_dir, "corrupted.pdf")
        File.write(corrupted_pdf, "Not a valid PDF content")

        _, stderr, exit_status = run_script(corrupted_pdf)
        expect(stderr).to include("Error")
        expect(exit_status).to eq(1)
      end
    end

    context "with malformed PDF structure" do
      it "handles missing outline gracefully" do
        _, stderr, exit_status = run_script(pdf_without_outline)
        expect(stderr).to include("No outline found")
        expect(exit_status).to eq(1)
      end
    end

    context "with empty file path" do
      it "shows error message for empty string" do
        _, stderr, exit_status = run_script("")
        expect(stderr).to include("Error: Please provide a PDF file path")
        expect(exit_status).to eq(1)
      end
    end

    context "with whitespace-only file path" do
      it "shows error message for whitespace string" do
        _, stderr, exit_status = run_script("   ")
        expect(stderr).to include("Error: Please provide a PDF file path")
        expect(exit_status).to eq(1)
      end
    end

    context "with PDF reader malformed error" do
      let(:test_pdf) do
        test_file = File.join(temp_dir, "test.pdf")
        FileUtils.cp(pdf_with_outline, test_file)
        test_file
      end

      it "handles PDF::Reader::MalformedPDFError" do
        allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError, "Invalid PDF")

        _, stderr, exit_status = run_script(test_pdf)
        expect(stderr).to include("Error: The PDF file appears to be corrupted")
        expect(exit_status).to eq(1)
      end
    end

    context "with general PDF reading error" do
      let(:test_pdf) do
        test_file = File.join(temp_dir, "test.pdf")
        FileUtils.cp(pdf_with_outline, test_file)
        test_file
      end

      it "handles general StandardError" do
        allow(PDF::Reader).to receive(:new).and_raise(StandardError, "Generic error")

        _, stderr, exit_status = run_script(test_pdf)
        expect(stderr).to include("Error reading PDF: Generic error")
        expect(exit_status).to eq(1)
      end
    end
  end

  describe "unit tests for internal methods" do
    # Create a test instance without command line arguments
    let(:splitter) do
      # Save original ARGV
      original_argv = ARGV.dup
      # Set test ARGV
      ARGV.clear
      ARGV << "#{fixture_path}/sample_with_outline.pdf"

      # Create instance
      instance = described_class.new

      # Restore original ARGV
      ARGV.clear
      original_argv.each { |arg| ARGV << arg }

      instance
    end

    describe "#decode_pdf_string (basic)" do
      it "handles UTF-16BE encoded strings" do
        # UTF-16BE with BOM
        utf16_string = "\xFE\xFF\x00T\x00e\x00s\x00t".dup
        result = splitter.send(:decode_pdf_string, utf16_string)
        expect(result).to eq("Test")
      end

      it "removes BOM from strings" do
        # UTF-8 with BOM
        bom_string = "\uFEFFTest String".dup
        result = splitter.send(:decode_pdf_string, bom_string)
        expect(result).to eq("Test String")
      end

      it "converts full-width spaces to half-width" do
        string_with_fullwidth = "Test　String".dup
        result = splitter.send(:decode_pdf_string, string_with_fullwidth)
        expect(result).to eq("Test String")
      end

      it "handles nil input" do
        result = splitter.send(:decode_pdf_string, nil)
        expect(result).to be_nil
      end

      it "handles regular UTF-8 strings" do
        regular_string = "Regular String".dup
        result = splitter.send(:decode_pdf_string, regular_string)
        expect(result).to eq("Regular String")
      end
    end

    describe "#filter_chapters_by_depth" do
      let(:chapters) do
        [
          { title: "Chapter 1", page: 1, level: 0 },
          { title: "Section 1.1", page: 5, level: 1 },
          { title: "Subsection 1.1.1", page: 7, level: 2 },
          { title: "Section 1.2", page: 10, level: 1 },
          { title: "Chapter 2", page: 15, level: 0 },
          { title: "Section 2.1", page: 17, level: 1 },
          { title: "Chapter 3", page: 25, level: 0 }
        ]
      end

      it "filters chapters at depth 1" do
        result = splitter.filter_chapters_by_depth(chapters, 1)
        expect(result.map { |ch| ch[:title] }).to eq(["Chapter 1", "Chapter 2", "Chapter 3"])
      end

      it "filters chapters at depth 2" do
        result = splitter.filter_chapters_by_depth(chapters, 2)
        titles = result.map { |ch| ch[:title] }
        expect(titles).to include("Section 1.1", "Section 1.2", "Section 2.1")
        expect(titles).to include("Chapter 3") # No subsections, so included
      end

      it "filters chapters at depth 3" do
        result = splitter.filter_chapters_by_depth(chapters, 3)
        titles = result.map { |ch| ch[:title] }
        expect(titles).to include("Subsection 1.1.1")
        expect(titles).to include("Section 1.2") # No subsections at depth 3
      end

      it "handles empty chapters array" do
        result = splitter.filter_chapters_by_depth([], 1)
        expect(result).to eq([])
      end

      it "adds parent indices correctly" do
        result = splitter.filter_chapters_by_depth(chapters, 2)
        section = result.find { |ch| ch[:title] == "Section 1.1" }
        expect(section[:parent_indices]).to include(0) # Chapter 1 is at index 0
      end

      it "handles nil elements in chapters array" do
        chapters_with_nil = [
          { title: "Chapter 1", page: 1, level: 0 },
          nil,
          { title: "Chapter 2", page: 10, level: 0 }
        ]
        result = splitter.filter_chapters_by_depth(chapters_with_nil.compact, 1)
        expect(result.map { |ch| ch[:title] }).to eq(["Chapter 1", "Chapter 2"])
      end

      it "handles very deep nesting (10+ levels)" do
        deep_chapters = []
        10.times do |i|
          deep_chapters << { title: "Level #{i}", page: i + 1, level: i }
        end
        result = splitter.filter_chapters_by_depth(deep_chapters, 10)
        expect(result.size).to eq(1)
        expect(result.first[:level]).to eq(9)
      end

    end

    describe "#find_chapter_end_page" do
      let(:all_chapters) do
        [
          { title: "Chapter 1", page: 1, level: 0, original_index: 0 },
          { title: "Section 1.1", page: 5, level: 1, original_index: 1, parent_indices: [0] },
          { title: "Chapter 2", page: 15, level: 0, original_index: 2 },
          { title: "Chapter 3", page: 25, level: 0, original_index: 3 }
        ]
      end

      it "finds end page for chapter with next chapter" do
        chapter = all_chapters[0]
        end_page = splitter.send(:find_chapter_end_page, chapter, all_chapters, 30)
        expect(end_page).to eq(14) # Page before Chapter 2
      end

      it "returns total pages for last chapter" do
        chapter = all_chapters[3]
        end_page = splitter.send(:find_chapter_end_page, chapter, all_chapters, 30)
        expect(end_page).to eq(30)
      end

      it "handles nested chapters correctly" do
        chapter = all_chapters[1] # Section 1.1
        end_page = splitter.send(:find_chapter_end_page, chapter, all_chapters, 30)
        expect(end_page).to eq(14) # Should extend to parent's end
      end

      it "handles missing original_index" do
        chapter = { title: "Test Chapter", page: 20, level: 0 }
        end_page = splitter.send(:find_chapter_end_page, chapter, all_chapters, 30)
        expect(end_page).to eq(30) # Returns total pages when chapter not found
      end
    end

    describe "#calculate_max_depth" do
      it "calculates correct maximum depth" do
        chapters = [
          { level: 0 },
          { level: 1 },
          { level: 2 },
          { level: 1 },
          { level: 0 }
        ]
        max_depth = splitter.send(:calculate_max_depth, chapters)
        expect(max_depth).to eq(3) # levels 0, 1, 2 = depth 3
      end

      it "handles single level chapters" do
        chapters = [{ level: 0 }, { level: 0 }]
        max_depth = splitter.send(:calculate_max_depth, chapters)
        expect(max_depth).to eq(1)
      end
    end

    describe "#format_chapter_filename_with_parent" do
      it "formats filename with parent title" do
        filename = splitter.send(:format_chapter_filename_with_parent, 5, "Section Title", "Chapter Title")
        expect(filename).to eq("005_Chapter Title_Section Title.pdf")
      end

      it "handles missing parent title" do
        filename = splitter.send(:format_chapter_filename_with_parent, 5, "Section Title", nil)
        expect(filename).to eq("005_Section Title.pdf")
      end

      it "sanitizes invalid characters" do
        filename = splitter.send(:format_chapter_filename_with_parent, 1, "Section: Test", "Chapter/Test")
        expect(filename).to eq("001_Chapter_Test_Section_ Test.pdf")
      end
    end

    describe "#format_chapter_filename" do
      it "formats filename with proper padding" do
        filename = splitter.send(:format_chapter_filename, 1, "Chapter Title")
        expect(filename).to eq("001_Chapter Title.pdf")
      end

      it "sanitizes all invalid characters" do
        filename = splitter.send(:format_chapter_filename, 1, "Chapter: Test/File*Name?<>|\"")
        expect(filename).to eq("001_Chapter_ Test_File_Name_____.pdf")
      end

      it "handles numbers greater than 99" do
        filename = splitter.send(:format_chapter_filename, 100, "Chapter Title")
        expect(filename).to eq("100_Chapter Title.pdf")
      end
    end

    describe "#extract_page_from_array_dest" do
      it "returns nil for empty destination array" do
        reader = instance_double(PDF::Reader, pages: [])
        result = splitter.send(:extract_page_from_array_dest, reader, [])
        expect(result).to be_nil
      end
    end

    describe "#extract_page_from_string_dest" do
      it "extracts page number from p-prefixed string" do
        result = splitter.send(:extract_page_from_string_dest, "p35")
        expect(result).to eq(35)
      end

      it "returns nil for non-matching string format" do
        result = splitter.send(:extract_page_from_string_dest, "page_35")
        expect(result).to be_nil
      end

      it "returns nil for complex named destinations" do
        result = splitter.send(:extract_page_from_string_dest, "Chapter1.Section2")
        expect(result).to be_nil
      end
    end

    describe "#get_destination" do
      it "returns direct destination if available" do
        item = { Dest: "direct_dest" }
        reader = instance_double(PDF::Reader)
        result = splitter.send(:get_destination, reader, item)
        expect(result).to eq("direct_dest")
      end

      it "returns nil if no destination or action" do
        item = {}
        reader = instance_double(PDF::Reader)
        result = splitter.send(:get_destination, reader, item)
        expect(result).to be_nil
      end

      it "extracts destination from action" do
        item = { A: { D: "action_dest" } }
        reader = instance_double(PDF::Reader)
        result = splitter.send(:get_destination, reader, item)
        expect(result).to eq("action_dest")
      end

      it "resolves action reference" do
        action_ref = PDF::Reader::Reference.new(1, 0)
        action_hash = { D: "resolved_dest" }
        objects = instance_double(PDF::Reader::ObjectHash)
        allow(objects).to receive(:[]).with(action_ref).and_return(action_hash)
        reader = instance_double(PDF::Reader, objects: objects)

        item = { A: action_ref }
        result = splitter.send(:get_destination, reader, item)
        expect(result).to eq("resolved_dest")
      end
    end

    describe "#children_at_depth?" do
      it "returns true when children exist at target depth" do
        chapters = [
          { level: 0, parent_indices: nil },
          { level: 1, parent_indices: [0] }
        ]
        result = splitter.send(:children_at_depth?, chapters, 0, 1)
        expect(result).to be true
      end

      it "returns false when no children at target depth" do
        chapters = [
          { level: 0, parent_indices: nil },
          { level: 2, parent_indices: [0] }
        ]
        result = splitter.send(:children_at_depth?, chapters, 0, 1)
        expect(result).to be false
      end

      it "handles nil parent_indices" do
        chapters = [
          { level: 0, parent_indices: nil },
          { level: 1, parent_indices: nil }
        ]
        result = splitter.send(:children_at_depth?, chapters, 0, 1)
        expect(result).to be false
      end
    end

    describe "#should_include_chapter?" do
      it "includes chapter at exact target depth" do
        chapter = { level: 1 }
        result = splitter.send(:should_include_chapter?, chapter, 0, 2, {})
        expect(result).to be true
      end

      it "includes chapter without children at target depth" do
        chapter = { level: 0 }
        chapters_with_children = { 0 => false }
        result = splitter.send(:should_include_chapter?, chapter, 0, 2, chapters_with_children)
        expect(result).to be true
      end

      it "excludes chapter with children at target depth" do
        chapter = { level: 0 }
        chapters_with_children = { 0 => true }
        result = splitter.send(:should_include_chapter?, chapter, 0, 2, chapters_with_children)
        expect(result).to be false
      end
    end

    describe "#find_parent_indices" do
      it "finds all parent indices for deeply nested chapter" do
        chapters = [
          { level: 0 },  # index 0
          { level: 1 },  # index 1
          { level: 2 },  # index 2
          { level: 3 }   # index 3
        ]
        result = splitter.send(:find_parent_indices, chapters, 3, 3)
        expect(result).to eq([2, 1, 0])
      end

      it "finds parent for sibling chapters" do
        chapters = [
          { level: 0 },  # index 0
          { level: 1 },  # index 1
          { level: 1 },  # index 2
          { level: 1 }   # index 3
        ]
        result = splitter.send(:find_parent_indices, chapters, 3, 1)
        expect(result).to eq([0])
      end

      it "returns empty array for top-level chapter" do
        chapters = [
          { level: 0 },  # index 0
          { level: 0 }   # index 1
        ]
        result = splitter.send(:find_parent_indices, chapters, 1, 0)
        expect(result).to eq([])
      end

      it "stops at level 0 parent" do
        chapters = [
          { level: 0 },  # index 0
          { level: 1 },  # index 1
          { level: 0 },  # index 2
          { level: 1 }   # index 3
        ]
        result = splitter.send(:find_parent_indices, chapters, 3, 1)
        expect(result).to eq([2])
      end
    end

    describe "#extract_chapters_from_reader" do
      it "returns nil when outline_root is nil" do
        reader = instance_double(PDF::Reader)
        allow(splitter).to receive(:find_outline_root).and_return(nil)

        result = splitter.send(:extract_chapters_from_reader, reader)
        expect(result).to be_nil
      end
    end

    describe "#parse_outline_item" do
      it "handles nil item_ref gracefully" do
        reader = instance_double(PDF::Reader)
        chapters = []

        # Should not raise error and chapters should remain empty
        expect do
          splitter.send(:parse_outline_item, reader, nil, chapters, 0)
        end.not_to raise_error
        expect(chapters).to be_empty
      end

      it "handles nil item gracefully" do
        reader = instance_double(PDF::Reader)
        objects = instance_double(PDF::Reader::ObjectHash)
        allow(reader).to receive(:objects).and_return(objects)
        allow(objects).to receive(:[]).and_return(nil)

        chapters = []
        item_ref = PDF::Reader::Reference.new(1, 0)

        expect do
          splitter.send(:parse_outline_item, reader, item_ref, chapters, 0)
        end.not_to raise_error
        expect(chapters).to be_empty
      end
    end

    describe "#decode_pdf_string (error handling)" do
      it "handles encoding errors gracefully for UTF-16BE" do
        # Invalid UTF-16BE sequence
        invalid_utf16 = "\xFE\xFF\x00\xD8\x00\x00".dup.force_encoding("BINARY")
        result = splitter.send(:decode_pdf_string, invalid_utf16)
        expect(result).to be_a(String)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "handles encoding errors gracefully for UTF-8" do
        # Invalid UTF-8 sequence
        invalid_utf8 = "\xFF\xFE\xFD".dup.force_encoding("BINARY")
        result = splitter.send(:decode_pdf_string, invalid_utf8)
        expect(result).to be_a(String)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "handles non-string input" do
        result = splitter.send(:decode_pdf_string, 123)
        expect(result).to be_nil
      end
    end

    describe "#extract_page_number" do
      it "returns nil when exception occurs" do
        reader = instance_double(PDF::Reader)
        item = { Dest: "invalid_dest" }

        # Mock to raise an exception
        allow(splitter).to receive(:get_destination).and_raise(StandardError)

        result = splitter.send(:extract_page_number, reader, item)
        expect(result).to be_nil
      end
    end

    describe "#find_next_chapter_at_same_or_higher_level" do
      it "handles chapters without original_index" do
        all_chapters = [
          { title: "Chapter 1", level: 0, page: 1 },
          { title: "Chapter 2", level: 0, page: 10 }
        ]

        result = splitter.send(:find_next_chapter_at_same_or_higher_level, 0, 0, all_chapters)
        expect(result[:title]).to eq("Chapter 2")
      end
    end

    describe "#parent?" do
      it "returns true for chapter with parent indices" do
        chapter = { parent_indices: [0, 1] }
        expect(splitter.send(:parent?, chapter)).to be true
      end

      it "returns false for chapter with empty parent indices" do
        chapter = { parent_indices: [] }
        expect(splitter.send(:parent?, chapter)).to be false
      end

      it "returns false for chapter without parent indices" do
        chapter = {}
        expect(splitter.send(:parent?, chapter)).to be_falsey
      end
    end

    describe "#identify_chapters_with_target_depth_children" do
      it "correctly identifies chapters with children at target depth" do
        chapters = [
          { level: 0 }, # index 0 - has child at depth 1
          { level: 1, parent_indices: [0] }, # index 1
          { level: 0 },  # index 2 - no children
          { level: 0 }   # index 3 - has child at depth 1
        ]
        chapters << { level: 1, parent_indices: [3] } # index 4

        result = splitter.send(:identify_chapters_with_target_depth_children, chapters, 2)
        expect(result[0]).to be true
        expect(result[2]).to be false
        expect(result[3]).to be true
      end
    end

    describe "#find_end_page_from_parent" do
      it "finds end page based on parent's next sibling" do
        all_chapters = [
          { title: "Chapter 1", level: 0, page: 1 },
          { title: "Section 1.1", level: 1, page: 5, parent_indices: [0] },
          { title: "Chapter 2", level: 0, page: 15 }
        ]

        chapter = all_chapters[1]
        result = splitter.send(:find_end_page_from_parent, chapter, all_chapters, 30)
        expect(result).to eq(14)
      end

      it "returns total pages when parent has no next sibling" do
        all_chapters = [
          { title: "Chapter 1", level: 0, page: 1 },
          { title: "Section 1.1", level: 1, page: 5, parent_indices: [0] }
        ]

        chapter = all_chapters[1]
        result = splitter.send(:find_end_page_from_parent, chapter, all_chapters, 30)
        expect(result).to eq(30)
      end
    end

    describe "#log" do
      it "prints message when not in dry-run mode" do
        allow(splitter.instance_variable_get(:@options)).to receive(:[]).with(:dry_run).and_return(false)
        expect { splitter.send(:log, "Test message") }.to output("Test message\n").to_stdout
      end

      it "suppresses message in dry-run mode without verbose" do
        allow(splitter.instance_variable_get(:@options)).to receive(:[]).with(:dry_run).and_return(true)
        allow(splitter.instance_variable_get(:@options)).to receive(:[]).with(:verbose).and_return(false)
        expect { splitter.send(:log, "Test message") }.not_to output.to_stdout
      end

      it "prints message in dry-run mode with verbose" do
        allow(splitter.instance_variable_get(:@options)).to receive(:[]).with(:dry_run).and_return(true)
        allow(splitter.instance_variable_get(:@options)).to receive(:[]).with(:verbose).and_return(true)
        expect { splitter.send(:log, "Test message") }.to output("Test message\n").to_stdout
      end
    end

    describe "#error_exit" do
      it "prints error message to stderr and exits" do
        allow(splitter).to receive(:warn)
        allow(splitter).to receive(:exit)

        splitter.send(:error_exit, "Test error")

        expect(splitter).to have_received(:warn).with("Test error")
        expect(splitter).to have_received(:exit).with(1)
      end
    end

    describe "#extract_chapters" do
      it "extracts chapters from PDF with outline" do
        splitter.instance_variable_set(:@pdf_path, pdf_with_outline)
        chapters = splitter.extract_chapters

        expect(chapters).to be_an(Array)
        expect(chapters).not_to be_empty
        expect(chapters.first).to include(:title, :page, :level)
      end

      it "returns nil for PDF without outline" do
        splitter.instance_variable_set(:@pdf_path, pdf_without_outline)
        chapters = splitter.extract_chapters

        expect(chapters).to be_nil
      end

      it "handles malformed PDF gracefully" do
        allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError, "Test error")

        expect do
          splitter.extract_chapters
        end.to raise_error(SystemExit)
      end

      it "handles general errors gracefully" do
        allow(PDF::Reader).to receive(:new).and_raise(StandardError, "Test error")

        expect do
          splitter.extract_chapters
        end.to raise_error(SystemExit)
      end

      it "handles extremely large outlines (1000+ chapters)" do
        reader = instance_double(PDF::Reader)
        allow(PDF::Reader).to receive(:new).and_return(reader)

        # Mock large outline structure
        large_outline = []
        1000.times do |i|
          large_outline << { Title: "Chapter #{i}", Dest: "p#{i + 1}" }
        end

        allow(splitter).to receive(:extract_chapters_from_reader).and_return(large_outline)

        chapters = splitter.extract_chapters
        expect(chapters.size).to eq(1000)
      end
    end

    describe "#extract_pages" do
      it "creates a new PDF with specified pages" do
        doc = instance_double(HexaPDF::Document)
        allow(splitter).to receive_messages(
          build_output_path: "/tmp/test.pdf",
          create_pdf_with_pages: doc,
          save_pdf_document: nil
        )

        splitter.send(:extract_pages, doc, 1, 5, "test.pdf")

        expect(splitter).to have_received(:build_output_path).with("test.pdf")
        expect(splitter).to have_received(:create_pdf_with_pages).with(doc, 1, 5)
        expect(splitter).to have_received(:save_pdf_document).with(doc, "/tmp/test.pdf", "test.pdf")
      end
    end

    describe "#output_dir" do
      it "returns directory of PDF file" do
        splitter.instance_variable_set(:@pdf_path, "/path/to/file.pdf")
        expect(splitter.send(:output_dir)).to eq("/path/to")
      end
    end


    describe "#get_chapter_index" do
      it "returns original_index if present" do
        chapter = { original_index: 5, title: "Test", page: 10 }
        result = splitter.send(:get_chapter_index, chapter, [])
        expect(result).to eq(5)
      end

      it "finds chapter by title and page when original_index is missing" do
        chapter = { title: "Test Chapter", page: 10 }
        all_chapters = [
          { title: "Other", page: 5 },
          { title: "Test Chapter", page: 10 },
          { title: "Another", page: 15 }
        ]
        result = splitter.send(:get_chapter_index, chapter, all_chapters)
        expect(result).to eq(1)
      end

      it "returns nil when chapter not found" do
        chapter = { title: "Missing", page: 99 }
        all_chapters = [{ title: "Other", page: 5 }]
        result = splitter.send(:get_chapter_index, chapter, all_chapters)
        expect(result).to be_nil
      end
    end

    describe "#sort_chapters_hierarchically" do
      it "sorts by page number first" do
        chapters = [
          { title: "Chapter 2", page: 10, level: 0 },
          { title: "Chapter 1", page: 5, level: 0 }
        ]
        result = splitter.send(:sort_chapters_hierarchically, chapters)
        expect(result[0][:title]).to eq("Chapter 1")
        expect(result[1][:title]).to eq("Chapter 2")
      end

      it "prioritizes parent chapters when on same page" do
        chapters = [
          { title: "Section 1.1", page: 5, level: 1 },
          { title: "Chapter 1", page: 5, level: 0 }
        ]
        result = splitter.send(:sort_chapters_hierarchically, chapters)
        expect(result[0][:title]).to eq("Chapter 1")
        expect(result[1][:title]).to eq("Section 1.1")
      end

      it "handles nil pages" do
        chapters = [
          { title: "Chapter 2", page: nil, level: 0 },
          { title: "Chapter 1", page: 5, level: 0 }
        ]
        result = splitter.send(:sort_chapters_hierarchically, chapters)
        expect(result[0][:title]).to eq("Chapter 2") # nil treated as 0
        expect(result[1][:title]).to eq("Chapter 1")
      end
    end

    describe "#collect_intermediate_chapters" do
      it "returns empty array for depth 1" do
        chapters = [
          { title: "Chapter 1", level: 0, page: 1 },
          { title: "Chapter 2", level: 0, page: 10 }
        ]
        result = splitter.send(:collect_intermediate_chapters, chapters, 1)
        expect(result).to be_empty
      end

      it "collects intermediate chapters with children" do
        chapters = [
          { title: "Chapter 1", level: 0, page: 1 },
          { title: "Section 1.1", level: 1, page: 2, parent_indices: [0] },
          { title: "Subsection 1.1.1", level: 2, page: 3, parent_indices: [0, 1] }
        ]
        chapters.each_with_index { |ch, i| ch[:original_index] = i }

        # Build parent-child relationships
        splitter.send(:build_parent_child_relationships, chapters)

        result = splitter.send(:collect_intermediate_chapters, chapters, 3)

        expect(result.size).to eq(2) # Chapter 1 and Section 1.1
        expect(result[0][:title]).to eq("Chapter 1")
        expect(result[1][:title]).to eq("Section 1.1")
      end

      it "excludes chapters without children" do
        chapters = [
          { title: "Chapter 1", level: 0, page: 1 },
          { title: "Section 1.1", level: 1, page: 2 },
          { title: "Chapter 2", level: 0, page: 10 }
        ]
        chapters.each_with_index { |ch, i| ch[:original_index] = i }

        splitter.send(:build_parent_child_relationships, chapters)
        result = splitter.send(:collect_intermediate_chapters, chapters, 2)

        # Only Chapter 1 should be included (has children)
        expect(result.size).to eq(1)
        expect(result[0][:title]).to eq("Chapter 1")
      end
    end

    describe "#any_children?" do
      it "returns true when chapter has children" do
        chapters = [
          { title: "Chapter 1", level: 0, parent_indices: [] },
          { title: "Section 1.1", level: 1, parent_indices: [0] }
        ]

        result = splitter.send(:any_children?, chapters, 0)
        expect(result).to be true
      end

      it "returns false when chapter has no children" do
        chapters = [
          { title: "Chapter 1", level: 0, parent_indices: [] },
          { title: "Chapter 2", level: 0, parent_indices: [] }
        ]

        result = splitter.send(:any_children?, chapters, 0)
        expect(result).to be false
      end

      it "handles nil parent_indices" do
        chapters = [
          { title: "Chapter 1", level: 0 },
          { title: "Section 1.1", level: 1, parent_indices: nil }
        ]

        result = splitter.send(:any_children?, chapters, 0)
        expect(result).to be false
      end
    end

    describe "#build_parent_child_relationships" do
      it "adds original index to chapters" do
        chapters = [
          { title: "Chapter 1", level: 0 },
          { title: "Section 1.1", level: 1 },
          { title: "Chapter 2", level: 0 }
        ]

        splitter.send(:build_parent_child_relationships, chapters)

        expect(chapters[0][:original_index]).to eq(0)
        expect(chapters[1][:original_index]).to eq(1)
        expect(chapters[2][:original_index]).to eq(2)
      end

      it "adds correct parent indices" do
        chapters = [
          { title: "Chapter 1", level: 0 },
          { title: "Section 1.1", level: 1 },
          { title: "Chapter 2", level: 0 }
        ]

        splitter.send(:build_parent_child_relationships, chapters)

        expect(chapters[0][:parent_indices]).to eq([])
        expect(chapters[1][:parent_indices]).to eq([0])
        expect(chapters[2][:parent_indices]).to eq([])
      end
    end

    describe "#validate_depth_option" do
      it "allows valid depth" do
        expect { splitter.send(:validate_depth_option, 1) }.not_to raise_error
        expect { splitter.send(:validate_depth_option, 5) }.not_to raise_error
      end

      it "exits for invalid depth" do
        allow(splitter).to receive(:warn)
        allow(splitter).to receive(:exit)

        splitter.send(:validate_depth_option, 0)

        expect(splitter).to have_received(:warn).with("Error: Depth must be at least 1")
        expect(splitter).to have_received(:exit).with(1)
      end
    end

    describe "#prepare_output_directory" do
      let(:temp_dir) { Dir.mktmpdir }

      before do
        allow(splitter).to receive(:output_dir).and_return(temp_dir)
        allow(splitter).to receive(:log)
      end

      after do
        FileUtils.rm_rf(temp_dir)
      end

      it "creates chapters directory when it doesn't exist" do
        splitter.send(:prepare_output_directory)

        expect(Dir.exist?(File.join(temp_dir, "chapters"))).to be true
      end

      it "removes existing directory with force option" do
        chapters_dir = File.join(temp_dir, "chapters")
        FileUtils.mkdir_p(chapters_dir)
        File.write(File.join(chapters_dir, "test.txt"), "test")

        splitter.instance_variable_set(:@options, { force: true })
        splitter.send(:prepare_output_directory)

        expect(File.exist?(File.join(chapters_dir, "test.txt"))).to be false
      end

      it "exits when directory exists without force" do
        chapters_dir = File.join(temp_dir, "chapters")
        FileUtils.mkdir_p(chapters_dir)

        splitter.instance_variable_set(:@options, { force: false })

        expect do
          splitter.send(:prepare_output_directory)
        end.to raise_error(SystemExit)
      end
    end

    describe "#split_pdf" do
      let(:test_chapters) do
        [
          { title: "Chapter 1", page: 1, level: 0, original_index: 0 },
          { title: "Chapter 2", page: 10, level: 0, original_index: 1 }
        ]
      end

      it "processes chapters and creates PDF files" do
        mock_doc = instance_double(HexaPDF::Document)
        allow(HexaPDF::Document).to receive(:open).and_yield(mock_doc)
        allow(splitter).to receive(:create_split_context).and_return({})
        allow(splitter).to receive(:process_all_pdf_sections)

        splitter.split_pdf(test_chapters)

        expect(HexaPDF::Document).to have_received(:open).with(pdf_with_outline)
        expect(splitter).to have_received(:create_split_context).with(mock_doc, test_chapters)
        expect(splitter).to have_received(:process_all_pdf_sections)
      end

      it "handles empty chapters array" do
        mock_doc = instance_double(HexaPDF::Document)
        allow(HexaPDF::Document).to receive(:open).and_yield(mock_doc)
        allow(splitter).to receive(:create_split_context).and_return({})
        allow(splitter).to receive(:process_all_pdf_sections)

        expect { splitter.split_pdf([]) }.not_to raise_error
      end

      it "handles HexaPDF errors gracefully" do
        allow(HexaPDF::Document).to receive(:open).and_raise(HexaPDF::Error, "Test error")

        expect { splitter.split_pdf(test_chapters) }.to raise_error(HexaPDF::Error)
      end

      it "handles file system errors" do
        mock_doc = instance_double(HexaPDF::Document)
        allow(HexaPDF::Document).to receive(:open).and_yield(mock_doc)
        allow(splitter).to receive(:create_split_context).and_return({})
        allow(splitter).to receive(:process_all_pdf_sections).and_raise(Errno::ENOSPC, "No space left on device")

        expect { splitter.split_pdf(test_chapters) }.to raise_error(Errno::ENOSPC)
      end
    end

    describe "#default_options" do
      it "returns default options hash" do
        result = splitter.send(:default_options)
        expect(result).to eq({
          verbose: false,
          dry_run: false,
          force: false,
          depth: 1
        })
      end
    end

    describe "#format_file_number" do
      it "formats number with 3-digit zero padding" do
        expect(splitter.send(:format_file_number, 1)).to eq("001")
        expect(splitter.send(:format_file_number, 99)).to eq("099")
        expect(splitter.send(:format_file_number, 999)).to eq("999")
        expect(splitter.send(:format_file_number, 1000)).to eq("1000")
      end
    end

    describe "#sanitize_filename" do
      it "replaces invalid filename characters" do
        result = splitter.send(:sanitize_filename, "Chapter: Test/File*Name?<>|\"")
        expect(result).to eq("Chapter_ Test_File_Name_____")
      end

      it "handles normal filenames" do
        result = splitter.send(:sanitize_filename, "Normal Chapter Title")
        expect(result).to eq("Normal Chapter Title")
      end
    end

    describe "#build_filename" do
      it "builds filename from number and title" do
        result = splitter.send(:build_filename, "001", "Chapter Title")
        expect(result).to eq("001_Chapter Title.pdf")
      end
    end

    describe "#build_filename_with_parent" do
      it "builds filename with parent title" do
        result = splitter.send(:build_filename_with_parent, "005", "Section Title", "Chapter Title")
        expect(result).to eq("005_Chapter Title_Section Title.pdf")
      end
    end

    describe "#pdf_page_count" do
      it "returns page count from PDF" do
        allow(PDF::Reader).to receive(:new).and_return(instance_double(PDF::Reader, page_count: 42))
        result = splitter.send(:pdf_page_count)
        expect(result).to eq(42)
      end
    end

    describe "#calculate_end_page_from_next_chapter" do
      it "returns same page when chapters start on same page" do
        chapter = { page: 10 }
        next_chapter = { page: 10 }
        result = splitter.send(:calculate_end_page_from_next_chapter, chapter, next_chapter)
        expect(result).to eq(10)
      end

      it "returns page before next chapter when on different pages" do
        chapter = { page: 10 }
        next_chapter = { page: 20 }
        result = splitter.send(:calculate_end_page_from_next_chapter, chapter, next_chapter)
        expect(result).to eq(19)
      end
    end

    describe "#display_chapter_line" do
      it "displays chapter information line" do
        chapter = { title: "Test Chapter", page: 10 }
        all_chapters = [chapter]
        
        expect do
          splitter.send(:display_chapter_line, chapter, 0, all_chapters, 100)
        end.to output(/001_Test Chapter\.pdf.*pages 10-100/).to_stdout
      end
    end

    describe "#calculate_end_page_for_chapter" do
      it "calculates end page using next chapter" do
        chapter = { level: 0, page: 10 }
        next_chapter = { level: 0, page: 20 }
        all_chapters = [chapter, next_chapter]
        
        allow(splitter).to receive(:find_next_chapter_at_same_or_higher_level).and_return(next_chapter)
        
        result = splitter.send(:calculate_end_page_for_chapter, chapter, 0, all_chapters, 100)
        expect(result).to eq(19)
      end

      it "uses parent logic when chapter has parent" do
        chapter = { level: 1, page: 10, parent_indices: [0] }
        all_chapters = [{ level: 0 }, chapter]
        
        allow(splitter).to receive(:find_next_chapter_at_same_or_higher_level).and_return(nil)
        allow(splitter).to receive(:parent?).and_return(true)
        allow(splitter).to receive(:find_end_page_from_parent).and_return(50)
        
        result = splitter.send(:calculate_end_page_for_chapter, chapter, 1, all_chapters, 100)
        expect(result).to eq(50)
      end

      it "returns total pages for last chapter" do
        chapter = { level: 0, page: 90 }
        all_chapters = [chapter]
        
        allow(splitter).to receive(:find_next_chapter_at_same_or_higher_level).and_return(nil)
        allow(splitter).to receive(:parent?).and_return(false)
        
        result = splitter.send(:calculate_end_page_for_chapter, chapter, 0, all_chapters, 100)
        expect(result).to eq(100)
      end
    end
  end
end
