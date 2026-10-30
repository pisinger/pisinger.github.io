# frozen_string_literal: true

# Rouge lexer for Markdown fences tagged `kql` or `kusto` in this Jekyll site.
require 'rouge'

module Rouge
  module Lexers
    class Kusto < RegexLexer
      title 'Kusto Query Language'
      desc 'Kusto Query Language (KQL)'
      tag 'kusto'
      aliases 'kql', 'kusto-query-language'
      filenames '*.kql'
      mimetypes 'text/x-kusto'

      OPERATORS = %w[
        where project project-away project-keep project-rename project-reorder extend
        summarize mv-expand mv-apply make-series join lookup union find search
        parse parse-where parse-kv evaluate invoke partition scan serialize
        distinct count top take limit sort order by asc desc render as on kind
        hint let set declare print datatable externaldata getschema explain
        sample sample-distinct reduce graph-match fork materialize
      ].freeze

      WORD_OPERATORS = %w[
        and or not in !in between contains !contains has !has has_cs !has_cs
        startswith !startswith endswith !endswith matches regex like !like
        has_any has_all contains_cs startswith_cs endswith_cs
      ].freeze

      TYPES = %w[
        bool boolean datetime decimal dynamic guid int long real string timespan
        date time span
      ].freeze

      FUNCTIONS = %w[
        ago now todatetime totimespan datetime timespan datatable tobool toint tolong toreal
        tostring todynamic parse_json parse_xml strcat strcat_array split trim trim_start
        trim_end tolower toupper isempty isnotempty isnull isnotnull coalesce iff case
        iif bin bin_at count countif dcount dcountif sum sumif avg min max percentile
        percentiles make_set make_list make_bag arg_max arg_min pack pack_array
        array_length array_slice mv-expand bag_unpack extract extract_all parse_url
        parse_urlquery hash sha256 format_datetime format_timespan startofday endofday
        startofweek endofweek startofmonth endofmonth startofyear endofyear
      ].freeze

      KEYWORD_PATTERN = Regexp.union(OPERATORS.sort_by { |word| -word.length })
      WORD_OPERATOR_PATTERN = Regexp.union(WORD_OPERATORS.sort_by { |word| -word.length })
      TYPE_PATTERN = Regexp.union(TYPES)
      FUNCTION_PATTERN = Regexp.union(FUNCTIONS.sort_by { |word| -word.length })

      state :root do
        rule %r/\s+/, Text
        rule %r{//.*?$}, Comment::Single
        rule %r{/\*.*?\*/}m, Comment::Multiline
        rule %r/@?"(?:\\.|""|[^"])*"/, Str::Double
        rule %r/@?'(?:\\.|''|[^'])*'/, Str::Single
        rule %r/\b(?:true|false|null)\b/i, Keyword::Constant
        # Keep ISO-8601 Kusto datetime literals together. Without this, Rouge
        # splits date/time punctuation and can mark digits as Error tokens.
        rule %r/\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?\b/i, Literal::Date
        rule %r/\b\d+(?:\.\d+)?(?:ms|d|h|m|s)\b/i, Num::Integer
        rule %r/\b\d+\.\d+(?:[eE][+-]?\d+)?\b/, Num::Float
        rule %r/\b\d+(?:[eE][+-]?\d+)?\b/, Num::Integer
        rule %r/\b(?:#{TYPE_PATTERN})\b/i, Keyword::Type
        rule %r/\b(?:#{WORD_OPERATOR_PATTERN})\b/i, Operator::Word
        rule %r/\b(?:#{FUNCTION_PATTERN})\b(?=\s*\()/i, Name::Function
        rule %r/\b(?:#{KEYWORD_PATTERN})\b/i, Keyword
        rule %r/\$[A-Za-z_][A-Za-z0-9_]*/, Name::Variable
        rule %r/[A-Za-z_][A-Za-z0-9_]*/, Name
        rule %r/==|!=|<>|<=|>=|=~|!~|[=<>+*\/%|\-]/, Operator
        rule %r/[{}()\[\],.;:]/, Punctuation
      end
    end
  end
end
