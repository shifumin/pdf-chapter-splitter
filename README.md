# PDF Chapter Splitter

A Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs. Perfect for breaking down large documents like textbooks, manuals, or reports into manageable chapter-based files.

## Features

- 📖 Automatically detects chapters from PDF outline/bookmarks
- ✂️ Splits PDF into individual chapter files
- 🏗️ Flexible depth-based splitting (split by chapters, sections, or subsections)
- 🇯🇵 Supports Japanese and international character sets
- 📋 Handles front matter and appendices
- 🔍 Dry-run mode to preview splitting before execution
- 💪 Force mode to overwrite existing output
- 📊 Verbose mode for detailed progress tracking

## Requirements

- Ruby 3.4.4 or higher
- Bundler

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/pdf-chapter-splitter.git
cd pdf-chapter-splitter
```

2. Install dependencies:
```bash
bundle install
```

## Usage

### Basic Usage

```bash
bundle exec ruby pdf_chapter_splitter.rb document.pdf
```

This will:
1. Read the PDF's outline structure
2. Create a `chapters/` directory in the same location as the PDF
3. Split the PDF into individual chapter files

### Command Line Options

```bash
-d, --depth LEVEL  # Split at specified depth level (default: 1)
-n, --dry-run      # Preview what would be done without actually splitting
-f, --force        # Remove existing chapters/ directory if it exists
-v, --verbose      # Show detailed progress information
-c, --complete     # Include complete section content until next section starts
-h, --help         # Display help message
```

### Understanding Depth Levels

The `--depth` option controls how deeply the tool splits your PDF based on its outline hierarchy:

**Example PDF Structure:**
```
Chapter 1: Introduction
  ├── 1.1 Background
  ├── 1.2 Motivation
  │    ├── 1.2.1 Historical Context
  │    └── 1.2.2 Current Challenges
  └── 1.3 Overview
Chapter 2: Methodology
  ├── 2.1 Research Design
  └── 2.2 Data Collection
Chapter 3: Results
```

**Depth 1 (default):** Creates PDFs for chapters only
- `001_Chapter 1_ Introduction.pdf` (pages 1-50)
- `002_Chapter 2_ Methodology.pdf` (pages 51-80)
- `003_Chapter 3_ Results.pdf` (pages 81-120)

**Depth 2:** Creates PDFs for chapters AND sections
- `001_Chapter 1_ Introduction.pdf` (pages 1-50) - full chapter
- `002_Chapter 1_ Introduction_1.1 Background.pdf` (pages 1-15)
- `003_Chapter 1_ Introduction_1.2 Motivation.pdf` (pages 16-35)
- `004_Chapter 1_ Introduction_1.3 Overview.pdf` (pages 36-50)
- `005_Chapter 2_ Methodology.pdf` (pages 51-80) - full chapter
- `006_Chapter 2_ Methodology_2.1 Research Design.pdf` (pages 51-65)
- `007_Chapter 2_ Methodology_2.2 Data Collection.pdf` (pages 66-80)
- `008_Chapter 3_ Results.pdf` (pages 81-120) - no sections, so only full chapter

**Depth 3:** Creates PDFs for chapters, sections, AND subsections
- All files from depth 2, plus:
- `009_Chapter 1_ Introduction_1.2.1 Historical Context.pdf` (pages 16-25)
- `010_Chapter 1_ Introduction_1.2.2 Current Challenges.pdf` (pages 26-35)

### Examples

Preview splitting without creating files:
```bash
bundle exec ruby pdf_chapter_splitter.rb -n document.pdf
```

Split at section level (depth 2):
```bash
bundle exec ruby pdf_chapter_splitter.rb -d 2 document.pdf
```

Force overwrite existing output:
```bash
bundle exec ruby pdf_chapter_splitter.rb -f document.pdf
```

Show detailed progress:
```bash
bundle exec ruby pdf_chapter_splitter.rb -v document.pdf
```

Combine options (preview section-level split with verbose output):
```bash
bundle exec ruby pdf_chapter_splitter.rb -d 2 -n -v document.pdf
```

### The --complete Option

By default, when splitting sections, each PDF contains only the pages from the section's start up to (but not including) the next section's start page. The `--complete` option changes this behavior to include all pages up to where the next section begins.

**Without --complete (default):**
- Section 9.8.1 starting on page 171, with 9.8.2 starting on page 172
- Result: `9.8.1.pdf` contains only page 171

**With --complete:**
- Section 9.8.1 starting on page 171, with 9.8.2 starting on page 172
- Result: `9.8.1.pdf` contains pages 171-172 (includes content until the next section)

This is useful when section content flows across multiple pages and you want each PDF to contain the complete section content.

```bash
bundle exec ruby pdf_chapter_splitter.rb -d 4 -c document.pdf
```

## Output Format

The tool creates files with the following naming convention:

- `000_前付け.pdf` - Front matter (pages before the first chapter)
- `001_Chapter_Title.pdf` - Regular chapters with 3-digit numbering
- `999_付録.pdf` - Appendix (pages after the last chapter)

Invalid filename characters (`/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) are automatically replaced with underscores.

**Note:** When using depth levels 2 or higher, filenames include parent context as shown in the "Understanding Depth Levels" section above.

## How It Works

1. **Outline Detection**: The tool reads the PDF's built-in outline/bookmark structure
2. **Chapter Identification**: Identifies chapters at the specified depth level (default: top-level)
3. **Intelligent Splitting**: Based on the depth level, creates appropriate PDF files as shown in the examples above
4. **Page Range Calculation**: Determines accurate page boundaries for each section, handling edge cases like chapters starting on the same page
5. **PDF Splitting**: Creates new PDF files for each section, preserving original metadata

## Requirements for PDFs

- PDFs must have a proper outline/bookmark structure
- The tool relies on the PDF's internal navigation structure
- PDFs without outlines will show an error message

## Development

### Generating Test PDFs

```bash
bundle exec ruby spec/support/generate_test_pdfs.rb
```

### Running Tests

```bash
bundle exec rspec
```

### Running Linter

```bash
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues
```

## Troubleshooting

### "No outline found in the PDF file"
The PDF doesn't have bookmarks/outline. This tool requires PDFs with proper chapter structure.

### Depth level considerations
- The tool automatically adjusts if the specified depth exceeds the PDF's maximum depth
- Chapters without subsections at the target depth are output as complete chapters
- Use verbose mode (`-v`) to see informational messages about these adjustments

### "chapters directory already exists"
Use the `--force` option to overwrite existing output, or manually remove the directory.

### Encoding Issues
The tool handles UTF-16BE and UTF-8 encoded text. If you encounter issues with special characters, please report them.

### Invalid Command-Line Arguments
The tool validates all command-line arguments and provides clear error messages for invalid inputs (e.g., non-integer depth values).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Dependencies

This project uses the following libraries:
- HexaPDF (AGPL-3.0) - Used for PDF manipulation
- Other dependencies are listed in Gemfile with their respective licenses

