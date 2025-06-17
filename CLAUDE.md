# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Chapter Splitter is a Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs.

## Common Commands

```bash
# Install dependencies
bundle install

# Run the script
bundle exec ruby pdf_chapter_splitter.rb [options] input.pdf

# Run tests
bundle exec rspec
bundle exec rspec spec/pdf_chapter_splitter_spec.rb:42  # Run specific test

# Run linter
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues
bundle exec rubocop -A  # Auto-fix with unsafe corrections

# Generate test PDFs (required before running tests)
bundle exec ruby spec/support/generate_test_pdfs.rb

# Debug PDF outline structure
bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').outline"
```

## Architecture

### Core Class: PDFChapterSplitter

**Public API:**
- `initialize` - Parses command-line options and validates input
- `run` - Main entry point for PDF processing
- `extract_chapters` - Extracts chapter information from PDF outline
- `filter_chapters_by_depth(chapters, depth)` - Filters chapters by hierarchy depth
- `split_pdf(chapters)` - Splits PDF into individual chapter files

### Key Implementation Details

1. **PDF Processing Flow:**
   - Parse command-line options with OptionParser
   - Extract outline structure using pdf-reader's low-level objects API
   - Filter chapters based on specified depth level
   - Calculate page ranges for each chapter/section
   - Split PDF using HexaPDF, preserving metadata

2. **Outline Parsing:**
   - Uses pdf-reader's objects API to access PDF catalog
   - Recursively traverses outline items via First/Next references
   - Handles both direct destinations and action-based destinations
   - Extracts page numbers from PDF::Reader::Reference objects

3. **Character Encoding:**
   - Detects and handles UTF-16BE encoded text (common in Japanese PDFs)
   - Removes BOM (Byte Order Mark) characters
   - Converts full-width spaces to half-width

4. **Depth-Based Splitting:**
   - Depth 1: Top-level chapters only
   - Depth 2+: Includes intermediate levels automatically
   - Chapters without children at target depth are included as complete chapters
   - Parent context included in filenames for nested sections

5. **File Naming:**
   - 3-digit padding: `000_前付け.pdf`, `001_Chapter.pdf`, `999_付録.pdf`
   - Invalid characters (`/:*?"<>|`) replaced with underscores
   - Nested sections include parent context: `002_Chapter1_Section1.1.pdf`

### Critical Methods

**`filter_chapters_by_depth`:**
- Builds parent-child relationships via `parent_indices`
- Includes chapters at target depth
- Includes parent chapters that have no children at target depth
- Maintains original order with `original_index`

**`find_chapter_end_page`:**
- Finds next chapter at same or higher level
- For nested chapters, checks parent's next sibling
- Handles edge cases where chapters start on same page
- Respects `--complete` option for inclusive page ranges

**`sort_chapters_hierarchically`:**
- Primary sort: page number
- Secondary sort: hierarchy level (parents before children)
- Tertiary sort: original index (maintains PDF outline order)

### Error Handling

Handles specific error types:
- `PDF::Reader::MalformedPDFError` - Corrupted PDFs
- `PDF::Reader::InvalidObjectError` - Invalid PDF structure
- `NoMethodError` - Unexpected PDF structure (specific checks for `objects` and `[]`)
- Command-line validation errors
- File system errors (missing files, existing directories)

## Testing Strategy

**Test Organization:**
- `spec/pdf_chapter_splitter_spec.rb` - Main test suite (1700+ lines, 145+ tests)
- `spec/support/generate_test_pdfs.rb` - Generates test PDFs with various structures
- `spec/fixtures/` - Generated test PDFs (not checked in)

**Key Test Scenarios:**
- Multiple depth levels (1-10+)
- Same-page chapters
- Missing page numbers
- Japanese/UTF-16BE encoding
- Complex nested outlines
- Edge cases (empty titles, nil pages, deep nesting)

**Running Specific Tests:**
```bash
bundle exec rspec -fd  # Full documentation format
bundle exec rspec --only-failures  # Re-run failed tests
```

## Code Quality

**RuboCop Configuration:**
- Ruby 3.4 target
- 120 character line limit
- RSpec/ExampleLength: Max 16 lines
- Test support files excluded from complexity metrics
- Double quotes enforced for strings

**Testing Requirements:**
- Test public API, not private implementation
- Each test should have single responsibility
- Use descriptive contexts and examples
- Mock external dependencies when appropriate

## Known Issues

1. **Prawn Circular Dependency Warning**: Appears during test runs due to Prawn 2.5.0 internal issue. Safe to ignore - only affects test PDF generation, not production code.

2. **HexaPDF License**: Uses AGPL-3.0 license. Commercial users should consider HexaPDF's commercial license.

3. **Appendix Detection**: Simplified - assumes all pages after last chapter are appendix.

4. **Named Destinations**: Complex named destinations (non-numeric) may fail to extract page numbers.

## Development Workflow

1. Make changes to implementation
2. Run tests: `bundle exec rspec`
3. Fix RuboCop violations: `bundle exec rubocop -a`
4. Test with real PDFs using various options
5. Update documentation if behavior changes

## Recent Updates

### 2025-06-17
- Added test to verify PDF metadata preservation during splitting
- Enhanced test PDF generation to include metadata (title, author, subject, keywords, creator)
- Fixed RuboCop violations in test support files

### 2025-06-16
- Added `--complete` option for inclusive page ranges
- Enhanced SRP compliance with focused helper methods
- Fixed same-page chapter ordering issues
- Improved error handling specificity
- Test suite expanded to 145+ tests