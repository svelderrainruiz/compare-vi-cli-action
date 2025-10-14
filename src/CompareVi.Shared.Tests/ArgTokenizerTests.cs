using System.Linq;
using CompareVi.Shared;
using Xunit;

namespace CompareVi.Shared.Tests
{
    public class ArgTokenizerTests
    {
        [Fact]
        public void Tokenize_SplitsAndRespectsQuotes()
        {
            var input = "foo -x=1 \"bar baz\"";
            var tokens = ArgTokenizer.Tokenize(input).ToArray();

            Assert.Equal(new[] { "foo", "-x=1", "bar baz" }, tokens);
        }

        [Fact]
        public void Normalize_SplitsFlagEquals()
        {
            var tokens = ArgTokenizer.Tokenize("foo -x=1");
            var norm = ArgTokenizer.NormalizeFlagValuePairs(tokens).ToArray();
            Assert.Equal(new[] { "foo", "-x", "1" }, norm);
        }
    }
}

