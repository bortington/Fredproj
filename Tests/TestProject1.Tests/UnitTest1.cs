using Fredproj.WebApi.Models;

namespace TestProject1
{
    public class Tests
    {
        [SetUp]
        public void Setup()
        {
        }

        [Test]
        public void Test1()
        {
            Assert.Pass();
        }

        [Test]
        public void Person_exists_when_added()
        {
            SillyPersonRegister r = new();

            var p = new Person();
            p.Name = "Fred";


            r.AddPerson(p);

            Assert.True(p.Exists);
        }
    }
}