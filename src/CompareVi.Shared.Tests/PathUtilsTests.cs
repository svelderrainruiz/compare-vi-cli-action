using CompareVi.Shared;
using Xunit;

namespace CompareVi.Shared.Tests
{
    public class PathUtilsTests
    {
        [Fact]
        public void Quote_AddsQuotes_WhenSpacesPresent()
        {
            var input = "C:/Program Files/Test Folder/file.txt";
            var quoted = PathUtils.Quote(input);
            Assert.StartsWith("\"", quoted);
            Assert.EndsWith("\"", quoted);
        }

        [Fact]
        public void NormalizeWindowsPath_PreservesNonWindows()
        {
            var input = "/usr/local/bin";
            var normalized = PathUtils.NormalizeWindowsPath(input);
            // On non-Windows, returns same string; on Windows, this path is not a drive/UNC prefix
            Assert.Equal(input, normalized);
        }
    }
}

