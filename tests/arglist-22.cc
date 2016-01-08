// Check that inexpr-statement isn't found on {...} in a templated
// declaration.
auto bad1 = f<1>(a,
                 {1, 2});
auto bad2 = f<1>(a,
                 b,
                 {1, 2});
auto bad4 = f <3> (a,
                   b,
                   {1, 2},
                   c);
auto weird1 = f<3
                >(a,
                  b,
                  {1, 2},
                  c);
