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
        expect(stdout).to include("01_Chapter 1_ Introduction.pdf")
        expect(stdout).to include("02_Chapter 2_ Getting Started.pdf")
        expect(stdout).to include("03_Chapter 3_ Advanced Topics.pdf")
      end

      it "detects front matter" do
        stdout, = run_script("--dry-run", test_pdf)
        expect(stdout).to include("00_前付け.pdf")
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

          expect(File.exist?(File.join(chapters_dir, "00_前付け.pdf"))).to be true
          expect(File.exist?(File.join(chapters_dir, "01_Chapter 1_ Introduction.pdf"))).to be true
          expect(File.exist?(File.join(chapters_dir, "02_Chapter 2_ Getting Started.pdf"))).to be true
          expect(File.exist?(File.join(chapters_dir, "03_Chapter 3_ Advanced Topics.pdf"))).to be true
        end

        it "creates valid PDF files" do
          run_script(test_pdf)
          chapters_dir = File.join(temp_dir, "chapters")

          pdf_file = File.join(chapters_dir, "01_Chapter 1_ Introduction.pdf")
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
        expect(File.exist?(File.join(chapters_dir, "01_Chapter 1_ Introduction.pdf"))).to be true
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
      expect(stdout).to include("top-level chapters")
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
      expect(stdout).to include("01_Chapter 1_ Introduction.pdf")
      expect(stdout).not_to include("01_Chapter 1: Introduction.pdf")
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
  end
end
