int a_gcc_extension (void)
{
    int a1 = (
    {
	int y = foo (); int z;
	if (y > 0) z = y;
	else z = - y;
	z;
    }
	);
    if ( ({
	int y = foo (); int z;
	y;
    }
	) )
	a1 = 17;
    return ({ int y = foo (); int z; y;
    y; // Bogus, but should be fixed generally.
    });
}
