﻿using System.Collections.Generic;
using Sodium;

namespace PetrolPump
{
    public static class CellExtensionMethods
    {
        public static Stream<T> Changes<T>(this Cell<T> cell)
        {
            return Operational.Value(cell).Snapshot(cell, (n, o) => EqualityComparer<T>.Default.Equals(o, n) ? Maybe.Nothing<T>() : Maybe.Just(n)).FilterMaybe();
        }
    }
}