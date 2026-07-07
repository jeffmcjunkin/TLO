using System;

namespace PaymentService
{
    // Minimal, legitimately-buildable console app. This is the "clean" HEAD of the
    // build-runner repo. The M8.1 supply-chain attack applies files/poison/* on top.
    public static class Program
    {
        public static void Main()
        {
            Console.WriteLine("payment-service build OK");
        }
    }
}
