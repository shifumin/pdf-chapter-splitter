# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Chapter Splitter is a Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs.

## Quick Start

```bash
# Install dependencies
bundle install

# Basic usage - split by top-level chapters
bundle exec ruby pdf_chapter_splitter.rb input.pdf

# Split at section level (depth 2)
bundle exec ruby pdf_chapter_splitter.rb -d 2 input.pdf

# Preview what will be done (dry-run)
bundle exec ruby pdf_chapter_splitter.rb -n input.pdf

# Force overwrite existing output
bundle exec ruby pdf_chapter_splitter.rb -f input.pdf
```

## CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `-d, --depth LEVEL` | Split at specified hierarchy level | 1 |
| `-n, --dry-run` | Show what would be done without doing it | false |
| `-f, --force` | Remove existing chapters directory if it exists | false |
| `-v, --verbose` | Show detailed progress | false |
| `-c, --complete` | Include all pages until next section starts | false |
| `-h, --help` | Show help message | - |

## Directory Structure

```
pdf-chapter-splitter/
├── pdf_chapter_splitter.rb  # Main script (single-file architecture)
├── Gemfile                  # Dependencies
├── .rubocop.yml            # Linter configuration
└── spec/
    ├── pdf_chapter_splitter_spec.rb  # Test suite (145+ tests)
    ├── spec_helper.rb
    ├── support/
    │   └── generate_test_pdfs.rb     # Test PDF generator
    └── fixtures/                      # Generated test PDFs (.gitignore)
```

## Dependencies

| Gem | Purpose | Notes |
|-----|---------|-------|
| **pdf-reader** | Read PDF outline/bookmarks | Extracts page numbers and titles |
| **hexapdf** | Split PDFs, preserve metadata | AGPL-3.0 license |
| **prawn** | Generate test PDFs | Development only |

## Architecture

### Processing Flow

```
Input PDF → [pdf-reader] → Extract Outline → Filter by Depth → Calculate Page Ranges → [hexapdf] → Split PDFs
                ↓
           Chapter Data
           { title:, page:, level:, original_index:, parent_indices: }
```

### Public API (pdf_chapter_splitter.rb)

| Method | Line | Description |
|--------|------|-------------|
| `initialize` | :13 | Parse CLI options and validate input |
| `run` | :19 | Main entry point |
| `filter_chapters_by_depth` | :25 | Filter chapters by hierarchy level |
| `extract_chapters` | :31 | Extract chapter info from PDF outline |
| `split_pdf` | :40 | Split PDF into individual files |

### Key Internal Methods

| Method | Line | Description |
|--------|------|-------------|
| `sort_chapters_hierarchically` | :311 | Sort by page, then original_index for same-page ordering |
| `find_chapter_end_page` | :747 | Calculate end page considering hierarchy |

### Implementation Details

1. **Outline Parsing:**
   - Uses pdf-reader's objects API to access PDF catalog
   - Recursively traverses outline items via First/Next references
   - Handles both direct destinations and action-based destinations

2. **Character Encoding:**
   - Detects and handles UTF-16BE encoded text (common in Japanese PDFs)
   - Removes BOM characters, converts full-width spaces

3. **Depth-Based Splitting:**
   - Depth 1: Top-level chapters only
   - Depth 2+: Includes intermediate levels automatically
   - Chapters without children at target depth are included as complete chapters

4. **File Naming:**
   - 3-digit padding: `000_前付け.pdf`, `001_Chapter.pdf`
   - Invalid characters (`/:*?"<>|`) replaced with underscores
   - Nested sections: `002_Chapter1_Section1.1.pdf`

## Testing

```bash
# REQUIRED: Generate test PDFs first (one-time setup)
bundle exec ruby spec/support/generate_test_pdfs.rb

# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/pdf_chapter_splitter_spec.rb:42

# Documentation format
bundle exec rspec -fd
```

**Key Test Scenarios:**
- Multiple depth levels (1-10+)
- Same-page chapters (ordering by original_index)
- Japanese/UTF-16BE encoding
- Edge cases: empty titles, nil pages, deep nesting

## Code Quality

```bash
# Run linter
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Auto-fix with unsafe corrections
bundle exec rubocop -A
```

**RuboCop Configuration:**
- Ruby 3.4 target
- 120 character line limit
- Double quotes enforced

## Implementation Guidelines

When modifying this codebase:

1. **Single-file architecture**: All logic stays in `pdf_chapter_splitter.rb`
2. **Public API stability**: Do not change signatures of public methods (initialize, run, extract_chapters, filter_chapters_by_depth, split_pdf)
3. **Error handling**: Catch specific error types, use `error_exit` for consistent error output
4. **Chapter data structure**: Always include `{ title:, page:, level:, original_index: }`
5. **Test coverage**: Add tests for new functionality, test public API only

## Known Issues

1. **Prawn Circular Dependency Warning**: Appears during test runs due to Prawn 2.5.0 internal issue. Safe to ignore.

2. **HexaPDF License**: Uses AGPL-3.0. Commercial users should consider HexaPDF's commercial license.

3. **Appendix Detection**: Simplified - assumes all pages after last chapter are appendix.

4. **Named Destinations**: Complex named destinations (non-numeric) may fail to extract page numbers.

## Debug Commands

```bash
# View PDF outline structure
bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').outline"

# Count total pages
bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').page_count"
```
