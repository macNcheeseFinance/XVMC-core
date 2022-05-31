Pool libraries are virtually copied from the pancakeswap autocompounding pool.

Masterchef libraries are copied from pancakeswap/goose.

The "standard" are the standard openzeppelin contract.

"modified" have a slight modificiation(the addition of transferXVMC function), which is a modification of the transferFrom function
Contracts that are trusted use the modified libraries(the transferXVMC function)

There was a complaint from one of the reviewers that the libraries(and interfaces) are messy. We focused on functionality and safety. 
The readibility and the way libraries/interfaces are handled can be improved.

Priority is shipping a SAFE, SECURE and FUNCTIONAL code, if i were to focus on all the nuances, it would have never happened.
