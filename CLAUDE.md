# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Chapter Splitter is a Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs. The tool is particularly useful for large documents like textbooks, manuals, or reports that need to be divided into smaller, chapter-based files.

## Project Status

The project is fully implemented with:
- Complete CLI tool with multiple options (--depth, --dry-run, --force, --verbose, --help)
- Flexible depth-based splitting (can split at any outline level)
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

# Run linter
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues

# Run the script
bundle exec ruby pdf_chapter_splitter.rb [options] input.pdf

# Examples:
bundle exec ruby pdf_chapter_splitter.rb document.pdf
bundle exec ruby pdf_chapter_splitter.rb -n document.pdf  # Dry run
bundle exec ruby pdf_chapter_splitter.rb -d 2 document.pdf  # Split at depth 2
bundle exec ruby pdf_chapter_splitter.rb -f document.pdf  # Force overwrite
bundle exec ruby pdf_chapter_splitter.rb -v document.pdf  # Verbose output
bundle exec ruby pdf_chapter_splitter.rb -d 2 -n -v document.pdf  # Combine options
```

## Architecture and Implementation Details

### Main Components

1. **PDFChapterSplitter Class**: The main class that orchestrates the entire process
   - **Public API Methods**:
     - `initialize`: Creates a new instance and parses command-line options
     - `run`: Main entry point that processes the PDF
     - `extract_chapters`: Extracts chapter information from PDF outline
     - `filter_chapters_by_depth`: Filters chapters based on specified depth level
     - `split_pdf`: Performs the actual PDF splitting using HexaPDF
   - **Key Private Methods**:
     - `parse_options`: Handles CLI argument parsing
     - Various helper methods for processing and organizing chapters

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
- `parent_indices`: Array of parent chapter indices (added during filtering)
- `original_index`: Original position in the full chapter list

#### filter_chapters_by_depth(chapters, depth)
Filters chapters based on the specified depth level:
- Returns chapters at the target depth
- If a parent chapter has no children at the target depth, includes the parent
- Maintains parent-child relationships for proper page range calculation

#### split_pdf(chapters)
Main splitting logic that:
1. Checks for front matter (pages before first chapter)
2. Processes each chapter with correct page ranges
3. Handles multi-level splits with parent context in filenames
4. Checks for appendix (pages after last chapter)
5. Creates appropriately named PDF files

#### find_chapter_end_page(chapter, all_chapters, total_pages)
Determines the end page for a chapter by:
- Finding the next chapter at the same or higher level
- For nested chapters, checking parent's next sibling
- Handling edge cases where chapters may not have original_index

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
- Invalid command-line arguments (e.g., non-integer depth values)
- PDF reading errors (handles both PDF::Reader::MalformedPDFError and general StandardError)

### File Naming Convention

Output files follow this pattern:
- `000_前付け.pdf` - Front matter (if exists)
- Sequential numbering for all chapters and sections (3-digit padding):
  - `001_Chapter1.pdf` - Complete chapter
  - `002_Chapter1_Section1.1.pdf` - Specific section
  - `003_Chapter1_Section1.2.pdf`
  - `004_Chapter2.pdf` - Complete chapter
  - etc.
- `999_付録.pdf` - Appendix (if exists)

Invalid filename characters (`/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) are replaced with `_`.

## Testing Strategy

The test suite covers:
1. **CLI Options**: Help, dry-run, force, verbose, depth
2. **Error Cases**: Missing files, non-PDF files, no outline, invalid depth
3. **PDF Processing**: Regular PDFs, Japanese PDFs, complex outlines
4. **Multi-level Splitting**: Different depth levels, parent-child relationships
5. **Edge Cases**: Front matter, appendix detection, chapters without subsections
6. **File Operations**: Directory creation, overwrite protection

Test PDFs are generated programmatically using Prawn (for content) and HexaPDF (for outlines).

### RuboCop Configuration

The project uses RuboCop for code quality with the following customizations:
- Test support files (`spec/support/generate_test_pdfs.rb`) are excluded from `Metrics/AbcSize` and `Metrics/MethodLength` constraints
  - This is intentional as PDF generation methods require complex setup for creating realistic test data
  - The exclusion allows maintaining strict standards for production code while being pragmatic about test utilities

## Performance Considerations

- Uses streaming/chunked processing where possible
- Only loads necessary pages into memory
- Efficient outline traversal

## Known Limitations

1. Appendix detection is simplified (assumes content after last chapter)
2. Requires PDFs to have proper outline/bookmark structure
3. Page number extraction may fail for complex named destinations
4. When splitting at deep levels, file names can become long due to parent context

## Debugging Tips

1. Use `--verbose` to see detailed processing information
2. Use `--dry-run` to preview splitting without file creation
3. Combine `--dry-run` with `--verbose` to see chapter hierarchy and splitting decisions
4. Check PDF outline structure with: `bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').outline"`
5. For encoding issues, examine raw PDF strings in debugger
6. Use different `--depth` values to understand the PDF's structure

## Recent Updates

### Latest Updates (2025-06-16)

#### 1. File Naming Enhancement
- Changed file numbering from 2-digit to 3-digit padding (e.g., `01_` → `001_`)
- Supports up to 999 chapters without numbering issues
- Applied to front matter (`000_`), chapters, and appendix (`999_`)

#### 2. Single Responsibility Principle Refactoring
- Refactored all methods to follow SRP strictly
- Split complex methods into focused, single-purpose functions
- Added new helper methods for better code organization:
  - File formatting helpers: `format_file_number`, `sanitize_filename`, `build_filename`
  - Option parsing helpers: `default_options`, `parse_command_line_options`, `validate_parsed_options`
  - Display helpers: `display_chapter_line`, `calculate_end_page_from_next_chapter`
  - PDF processing helpers: `pdf_page_count`, `calculate_end_page_for_chapter`

#### 3. Test Suite Enhancement
- Comprehensive test coverage with 128 tests, all passing
- Added tests for all refactored methods and edge cases
- Removed redundant tests for better maintainability
- Full coverage of public API and error handling

#### 4. Documentation Enhancement
- Added detailed depth level examples in README.md showing how different depth values affect PDF splitting
- Clarified the behavior with concrete examples of generated files for each depth level
- Reorganized Development section: moved "Generating Test PDFs" to the top, followed by tests and linter
- Removed test suite details for cleaner documentation

#### 5. Fixed Chapter Ordering for Same-Page Sections
- Fixed an issue where chapters at the same level starting on the same page could appear in reversed order (e.g., 9.6.2 before 9.6.1)
- Added `original_index` as a third sorting criterion in `sort_chapters_hierarchically` method
- Now maintains the original PDF outline order when chapters have the same page number and level
- Example: Sections 9.6.1 and 9.6.2 both starting on page 169 now appear in correct order
- Added test coverage for this edge case

#### 6. Code Quality Verification
- Confirmed all methods follow Single Responsibility Principle (SRP)
- Verified test coverage is comprehensive and necessary (128 tests, all passing)
- RuboCop compliance: zero violations across all files
- No redundant or missing tests identified

### Previous Updates (2025-06-15)

#### Public API and Code Quality
- **Public API clarification**: Moved helper methods to private, keeping only essential public methods (initialize, run, filter_chapters_by_depth, extract_chapters, split_pdf)
- **Test suite refinement**: Comprehensive edge case coverage including nil elements, deep nesting (10+ levels), missing fields
- **Fixed method duplication**: Removed duplicate method definitions that were causing conflicts
- **RuboCop compliance**: All files pass with zero violations

### Major Improvements (2025-06-15)

#### 1. Default All Hierarchy Levels
- Changed default behavior to always create PDFs for all hierarchy levels
- When splitting at depth 2+, automatically includes all parent levels
- Example: With `-d 4`, creates PDFs for chapters at levels 1, 2, 3, and 4
- Removed `--include-intermediate` option as this is now the default behavior

#### 2. Hierarchical Sorting
- Added hierarchical sorting to prioritize parent chapters before child sections
- When chapters start on the same page, parent chapters get lower file numbers
- Example: "5章" (level 1) comes before "5.1" (level 2) when both start on page 87

#### 3. Critical Bug Fixes
- **Page Range Calculation**: Fixed bug where end page could be before start page for chapters on the same page
- **Depth Filtering**: Fixed parent-child relationship building to correctly include all chapters without children at target depth
- **Character Encoding**: Improved handling of Japanese and UTF-16BE encoded text

#### 4. Code Quality Improvements
- **Single Responsibility Principle**: Refactored methods to follow SRP
  - `run` method split into focused helper methods
  - `prepare_chapters_for_processing` decomposed into smaller functions
  - Improved separation of concerns throughout the codebase
- **RuboCop Compliance**: Fixed all style violations

## Code Quality Standards

### Testing Requirements
- All public methods must have comprehensive test coverage
- Avoid testing private method implementation details (test through public interfaces)
- Error handling must be tested for all user-facing errors
- Integration tests should cover the full workflow
- Unit tests should be focused and test one thing at a time
- Consolidate duplicate tests to improve maintainability

### RuboCop Compliance
- Code must pass all RuboCop checks before committing
- Use `bundle exec rubocop -a` to auto-fix issues
- Custom configurations are defined in `.rubocop.yml`

## Known Issues

### Prawn Circular Dependency Warning
When running tests, you may see a warning about circular dependencies in the Prawn gem:
```
warning: loading in progress, circular require considered harmful - /path/to/prawn/font.rb
```

This is a known issue in Prawn 2.5.0 and does not affect the functionality of the tool. The warning occurs because:
- Prawn's internal font loading mechanism has a circular dependency
- This only appears during test runs when generating test PDFs
- The production code (pdf_chapter_splitter.rb) uses HexaPDF and pdf-reader, not Prawn

This warning can be safely ignored as it's an upstream issue in the Prawn library used only for test PDF generation.

## License and Dependencies

### Project License
This project is licensed under the MIT License - see the LICENSE file for details.

### Key Dependencies and Their Licenses
- **HexaPDF** (AGPL-3.0) - Used for PDF splitting functionality
  - This is a copyleft license that may affect commercial usage
  - Users planning commercial deployment should consider HexaPDF's commercial license
  - See: https://hexapdf.gettalong.org/commercial-license.html
- **pdf-reader** (MIT) - Used for PDF outline parsing
- **Prawn** and related gems - Used only for test PDF generation (not in production code)

### Public Repository Considerations
When making this repository public:
- No sensitive information is included in the codebase
- All test data is programmatically generated
- Personal information is limited to the copyright holder name in LICENSE
- The AGPL-3.0 dependency (HexaPDF) is clearly documented in README.md