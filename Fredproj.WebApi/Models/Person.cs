namespace Fredproj.WebApi.Models
{
    public class Person
    {
        public string Name { get; set; }

        public bool Exists { get; set; }
    }

    public interface IPersonRegister
    {
        void AddPerson(Person person);

        void UpdatePerson(Person person);
    }

    public class SillyPersonRegister : IPersonRegister
    {
        public void AddPerson(Person person)
        {
            person.Exists = true;
        }

        public void UpdatePerson(Person person)
        {
            person.Exists = false;
        }
    }

}
