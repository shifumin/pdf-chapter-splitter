# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Chapter Splitter is a Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs. The tool is particularly useful for large documents like textbooks, manuals, or reports that need to be divided into smaller, chapter-based files.

## Project Status

The project is fully implemented with:
- Complete CLI tool with multiple options (--dry-run, --force, --verbose, --help)
- PDF outline parsing using pdf-reader gem
- PDF splitting using hexapdf gem
- Comprehensive test suite with RSpec
- RuboCop configuration for code quality
- Support for Japanese and other UTF-16BE encoded PDFs

## Project Structure

```
pdf-chapter-splitter/
├── .ruby-version          # Ruby 3.4.4
├── Gemfile               # Dependencies
├── Gemfile.lock
├── README.md
├── CLAUDE.md             # This file
├── pdf_chapter_splitter.rb  # Main executable script
├── spec/
│   ├── spec_helper.rb
│   ├── pdf_chapter_splitter_spec.rb
│   ├── fixtures/         # Test PDF files
│   │   ├── sample_with_outline.pdf
│   │   ├── sample_without_outline.pdf
│   │   ├── japanese_with_outline.pdf
│   │   └── complex_outline.pdf
│   └── support/
│       └── generate_test_pdfs.rb  # Test PDF generator
└── .rubocop.yml          # Linter configuration
```

## Common Commands

```bash
# Install dependencies
bundle install

# Generate test PDFs (if needed)
bundle exec ruby spec/support/generate_test_pdfs.rb

# Run tests
bundle exec rspec
bundle exec rspec spec/pdf_chapter_splitter_spec.rb  # Specific file
bundle exec rspec spec/pdf_chapter_splitter_spec.rb:42  # Specific line

# Run linter
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues

# Run the script
bundle exec ruby pdf_chapter_splitter.rb [options] input.pdf

# Examples:
bundle exec ruby pdf_chapter_splitter.rb document.pdf
bundle exec ruby pdf_chapter_splitter.rb -n document.pdf  # Dry run
bundle exec ruby pdf_chapter_splitter.rb -f document.pdf  # Force overwrite
bundle exec ruby pdf_chapter_splitter.rb -v document.pdf  # Verbose output
```

## Architecture and Implementation Details

### Main Components

1. **PDFChapterSplitter Class**: The main class that orchestrates the entire process
   - `parse_options`: Handles CLI argument parsing using OptionParser
   - `extract_chapters`: Extracts chapter information from PDF outline
   - `split_pdf`: Performs the actual PDF splitting using HexaPDF

2. **PDF Outline Parsing**: Uses pdf-reader's low-level objects API to access PDF outline structure
   - `find_outline_root`: Locates the outline root in the PDF catalog
   - `parse_outline_item`: Recursively parses outline items
   - `extract_page_number`: Extracts page numbers from destinations

3. **Character Encoding Handling**: Special handling for Japanese and UTF-16BE encoded text
   - `decode_pdf_string`: Converts PDF strings to UTF-8
   - Handles both UTF-16BE with BOM and regular UTF-8 strings

4. **PDF Splitting**: Uses HexaPDF to create new PDFs for each chapter
   - `extract_pages`: Creates a new PDF with specific page ranges
   - Preserves metadata from original PDF

### Key Methods

#### extract_chapters
Extracts chapter information from the PDF outline. Returns an array of chapter hashes with:
- `title`: Chapter title
- `page`: Starting page number (1-indexed)
- `level`: Nesting level (0 for top-level chapters)

#### split_pdf(chapters)
Main splitting logic that:
1. Checks for front matter (pages before first chapter)
2. Processes each chapter with correct page ranges
3. Checks for appendix (pages after last chapter)
4. Creates appropriately named PDF files

#### decode_pdf_string(str)
Handles PDF string encoding, particularly important for:
- Japanese text (often UTF-16BE encoded)
- Removing BOMs (Byte Order Marks)
- Converting full-width spaces to half-width

### Error Handling

The tool provides clear error messages for:
- Missing PDF file
- Non-PDF files
- PDFs without outline/bookmarks
- Existing output directory (without --force)
- Malformed or corrupted PDFs

### File Naming Convention

Output files follow this pattern:
- `00_前付け.pdf` - Front matter (if exists)
- `01_ChapterTitle.pdf` - Regular chapters with 2-digit numbering
- `99_付録.pdf` - Appendix (if exists)

Invalid filename characters (`/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) are replaced with `_`.

## Testing Strategy

The test suite covers:
1. **CLI Options**: Help, dry-run, force, verbose
2. **Error Cases**: Missing files, non-PDF files, no outline
3. **PDF Processing**: Regular PDFs, Japanese PDFs, complex outlines
4. **Edge Cases**: Front matter, appendix detection
5. **File Operations**: Directory creation, overwrite protection

Test PDFs are generated programmatically using Prawn (for content) and HexaPDF (for outlines).

## Performance Considerations

- Uses streaming/chunked processing where possible
- Only loads necessary pages into memory
- Efficient outline traversal (stops at first level)

## Known Limitations

1. Only processes first-level chapters (nested sections are ignored)
2. Appendix detection is simplified (assumes content after last chapter)
3. Requires PDFs to have proper outline/bookmark structure
4. Page number extraction may fail for complex named destinations

## Debugging Tips

1. Use `--verbose` to see detailed processing information
2. Use `--dry-run` to preview splitting without file creation
3. Check PDF outline structure with: `bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').outline"`
4. For encoding issues, examine raw PDF strings in debugger