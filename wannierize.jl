module wannierize

const DO_PLOT = true # plot obstruction phases

if(DO_PLOT)
    using PyPlot
end

## Assumptions: the kpoints are contained in a NxNxN cartesian grid, the neighbor list must contain the six cartesian neighbors

## N1xN2xN3 grid, filename.mmn must contain the overlaps
## nbeg and nend specify the window to wannierize
## Input Mmn file is nband x nband x nkpt x nntot
## Output is (nwannier = nend - nbeg + 1) x nband x nkpt, padded with zeros
function make_wannier(nband,N1,N2,N3,nntot,filename,nbeg,nend)
    t1 = collect(0:N1-1)/N1
    t2 = collect(0:N2-1)/N2
    t3 = collect(0:N3-1)/N3
    Ntot = N1*N2*N3
    nwannier = nend-nbeg+1

    # We switch between a big index K=1:N^3 and three indices i,j,k = 1:N using these arrays
    K_to_ijk = zeros(Int64,Ntot,3)
    ijk_to_K = zeros(Int64,N1,N2,N3)
    for i=0:N1-1
        for j=0:N2-1
            for k=0:N3-1
                K = i*N2*N3+j*N3+k+1
                ijk_to_K[i+1,j+1,k+1] = K
                K_to_ijk[K,:] = [i+1 j+1 k+1]
            end
        end
    end

    A = zeros(Complex128,N1,N2,N3,nwannier,nwannier) # unitary rotation matrix at each k-point, (i,j,k) representation
    M = zeros(Complex128,Ntot,nntot,nwannier,nwannier) # overlap matrix, (K) representation
    neighbors = zeros(Int64,Ntot,nntot) # for each point, list of neighbors, (K) representation


    # ## In case we want to read an amn file at some point
    # amn = open("$filename.amn")
    # readline(amn)
    # readline(amn)
    # lines = readlines(amn)
    # for line in lines
    #     # print(line)
    #     arr = split(line)
    #     m = parse(Int64, arr[1])
    #     n = parse(Int64, arr[2])
    #     kpt = parse(Int64, arr[3])
    #     Aijkmn = parse(Float64, arr[4]) + im*parse(Float64, arr[5])
    #     A[K_to_ijk[kpt,1], K_to_ijk[kpt,2], K_to_ijk[kpt,3],m,n] = Aijkmn
    # end

    println("Reading $filename.mmn")
    mmn = open("$filename.mmn")
    readline(mmn) # skip headers
    readline(mmn)
    while !eof(mmn)
        for nneighbor = 1:nntot
            line = readline(mmn)
            arr = split(line)
            K = parse(Int64, arr[1])
            Kpb = parse(Int64, arr[2])
            neighbors[K,nneighbor,:] = Kpb
            for mn = 0:nband^2-1
                m,n = mod(mn,nband)+1, div(mn,nband)+1
                if (m > nend) || (m < nbeg) || (n > nend) || (n < nbeg)
                    # ignore band not to wannierize
                    readline(mmn)
                    continue
                else
                    line = readline(mmn)
                    arr = split(line)
                    ol = parse(Float64, arr[1]) + im*parse(Float64, arr[2])
                    M[K,nneighbor,m-nbeg+1,n-nbeg+1] = ol
                end
            end
        end
    end

    fill!(A,NaN) #protection: A must be filled by the algorithm

    # Computes overlap between two neighboring K points
    function overlap(K1,K2)
        for nneighbor=1:nntot
            if neighbors[K1,nneighbor] == K2
                return M[K1,nneighbor,:,:]
            end
        end
        error("No neighbors found")
    end
    # Computes the overlap between K1 and K2, rotated by A1 and A2 respectively
    function overlap(K1,K2,A1,A2)
        return (A1')*overlap(K1, K2)*A2
    end
    # Computes the overlap between K1 and K2, using the rotation contained in the array A
    function overlap_A(K1,K2)
        i1,j1,k1 = K1
        i2,j2,k2 = K2
        return overlap(ijk_to_K[i1,j1,k1],ijk_to_K[i2,j2,k2],A[i1,j1,k1,:,:], A[i2,j2,k2,:,:])
    end

    # Power of a unitary (or at least, normal) matrix A
    function powm(A,p)
        d,V = eig(A)
        return V*diagm(d.^p)*V'
    end

    # Normalize a matrix A to be unitary. If X is a matrix with orthogonal columns and A a non-singular matrix, then Löwdin-orthogonalizing X*A is equivalent to computing X*normalize(A)
    function normalize(A)
        U,S,V = svd(A)
        return U*V'
    end

    # Propagate A0, defined at the first kpt, to the given list of kpts.
    # Those must be neighbors, and only the first kpoint is assumed to have been rotated
    function propagate(A0, kpts)
        N = length(kpts)
        As = zeros(Complex128,N,nwannier,nwannier)
        As[1,:,:] = A0
        for i=2:N
            As[i,:,:] = normalize(overlap(kpts[i],kpts[i-1])*As[i-1,:,:])
            # println("Before/After")
            # println(norm(overlap(kpts[i],kpts[i-1])*As[i-1,:,:] - eye(Complex128,nwannier)))
            # println(norm(As[i,:,:]'*overlap(kpts[i],kpts[i-1])*As[i-1,:,:] - eye(Complex128,nwannier)))
        end
        return As
    end

    println("Filling (k,0,0)")
    A[:,1,1,:,:] = propagate(eye(nwannier), [ijk_to_K[i,1,1] for i=1:N1])

    # for i=2:N1
    #     println(norm(overlap_A([i-1,1,1],[i,1,1]) - eye(Complex128,nwannier)))
    # end

    # compute obstruction matrix
    Obs = normalize(overlap_A([N1,1,1],[1,1,1]))
    # and pull it back
    for i=1:N1
        A[i,1,1,:,:] = A[i,1,1,:,:]*powm(Obs,t1[i])
    end

    # # test
    # for i=2:N1
    #     println(norm(overlap_A([i-1,1,1],[i,1,1]) - eye(Complex128,nwannier)))
    # end
    # println(norm(overlap_A([N1,1,1],[1,1,1]) - eye(Complex128,nwannier)))


    println("Filling (k1,k2,0)")
    for i=1:N1
        A[i,:,1,:,:] = propagate(A[i,1,1,:,:], [ijk_to_K[i,j,1] for j=1:N2])
    end

    # corner obstruction
    Obs = normalize(overlap_A([1,N2,1],[1,1,1]))
    d,V = eig(Obs)
    logd = log(d)
    for i=1:nwannier
        if imag(logd[i]) < -pi+.1
            logd[i] = logd[i] + 2pi
        end
    end
    # pull it back
    for i=1:N1
        for j=1:N2
            # A[i,j,1,:,:] = A[i,j,1,:,:]*powm(Obs,t2[j])
            A[i,j,1,:,:] = A[i,j,1,:,:]*V*diagm(exp(t2[j]*logd))*V'
        end
    end

    # Pull back the line obstruction
    phases = zeros(N1,nwannier)
    for i=1:N1
        Obs = normalize(overlap_A([i,N2,1],[i,1,1])) #rotation at image point
        for j=1:N2
            A[i,j,1,:,:] = A[i,j,1,:,:]*powm(Obs,t2[j])
        end
        phases[i,:] = imag(log(eig(Obs)[1]))
    end

    if DO_PLOT
        figure()
        plot(phases,"x")
        savefig("wannierize_0_2D.pdf")
    end


    # phases = zeros(N1,nwannier)
    # for i=1:N1
    #     Obs = normalize(overlap_A([i,N2,1],[i,1,1])) #rotation at image point
    #     phases[i,:] = imag(log(eig(Obs)[1]))
    # end
    # figure()
    # plot(phases,"x")

    # omegaright = zeros(N1,N2)
    # omegaup = zeros(N1,N2)
    # for i=1:N1,j=1:N2
    #     right = i==N1 ? 1 : i+1
    #     up = j==N2 ? 1 : j+1
    #     omegaright[i,j] = norm(overlap_A([right,j,1],[i,j,1]) - eye(Complex128,nwannier))
    #     omegaup[i,j] = norm(overlap_A([i,up,1],[i,j,1]) - eye(Complex128,nwannier))
    # end
    # # figure()
    # matshow(omegaright)
    # colorbar()
    # matshow(omegaup)
    # colorbar()

        
    # Plot obstructions
    function plot_surface_obstructions(suffix="")
        if DO_PLOT && N3 != 1
            phases = zeros(N1,N2,nwannier)
            for i=1:N1,j=1:N2
                Obs = normalize(overlap_A([i,j,N3],[i,j,1])) #rotation at image point
                phases[i,j,:] = sort(imag(log(eig(Obs)[1])))
            end
            figure()
            xx = [t1[i] for i=1:N1,j=1:N2]
            yy = [t2[j] for i=1:N1,j=1:N2]
            for n=1:nwannier
                plot_surface(xx,yy,phases[:,:,n],rstride=1,cstride=1)
            end
            savefig("wannierize$suffix.pdf")
        end
    end

    println("Filling (k1,k2,k3)")
    for i=1:N1,j=1:N2
        A[i,j,:,:,:] = propagate(A[i,j,1,:,:], [ijk_to_K[i,j,k] for k=1:N3])
    end

    plot_surface_obstructions("_1_none")

    # Fix corner
    Obs = normalize(overlap_A([1,1,N3],[1,1,1]))
    d,V = eig(Obs)
    logd = log(d)
    for i =1:nwannier
        if imag(logd[i]) < -pi+.1
            logd[i] = logd[i] + 2pi
        end
    end
    for k=1:N3
        # fixer = powm(Obs,t3[k])
        fixer = V*diagm(exp(t3[k]*logd))*V'
        for i=1:N1,j=1:N2
            A[i,j,k,:,:] = A[i,j,k,:,:]*fixer
        end
    end

    plot_surface_obstructions("_2_corners")
    
    # Fix first edge
    for i=1:N1
        Obs = normalize(overlap_A([i,1,N3], [i,1,1]))
        for k=1:N3
            fixer = powm(Obs, t3[k])
            for j=1:N3
                A[i,j,k,:,:] = A[i,j,k,:,:]*fixer
            end
        end
    end
    # Fix second edge
    for j=1:N2
        Obs = normalize(overlap_A([1,j,N3], [1,j,1]))
        for k=1:N3
            fixer = powm(Obs, t3[k])
            for i=1:N1
                A[i,j,k,:,:] = A[i,j,k,:,:]*fixer
            end
        end
    end
    
    plot_surface_obstructions("_3_edges")
    
    # Fix whole surface
    for i=1:N1,j=1:N2
        Obs = normalize(overlap_A([i,j,N3],[i,j,1]))
        for k=1:N3
            A[i,j,k,:,:] = A[i,j,k,:,:]*powm(Obs,t3[k])
        end
    end
        
    plot_surface_obstructions("_4_surface")

    ## Output amn file
    out = open("$filename.amn","w")
    write(out, "Created by wannierize.jl bands $nbeg:$nend", string(now()), "\n")
    write(out, "$nband $Ntot $nwannier\n")
    for K=1:Ntot
        for n=1:nwannier
            for m = 1:nband
                if (m < nbeg) || (m > nend)
                    coeff = 0 # pad with zeros
                else
                    coeff = A[K_to_ijk[K,1], K_to_ijk[K,2], K_to_ijk[K,3],m-nbeg+1,n]
                end
                write(out, "$m $n $K $(real(coeff)) $(imag(coeff))\n")
            end
        end
    end
    close(out)
end

# Get parameters from mmn file
function read_parameters(filename, N1, N2, N3)
    mmn = open("$filename.mmn")
    readline(mmn) # skip header
    line = readline(mmn)
    nbandin,N3in,nntotin = split(line)
    nbandin,N3in,nntotin = parse(Int64,nbandin), parse(Int64,N3in), parse(Int64,nntotin)
    nband = nbandin
    # N = Int64(round(N3in^(1/3)))
    nntot = nntotin
    @assert N1*N2*N3 == N3in
    close(mmn)

    return nband,nntot
end
end

if(length(ARGS) >= 1)
    filename = ARGS[1]
    N1 = parse(Int64,ARGS[2])
    N2 = parse(Int64,ARGS[3])
    N3 = parse(Int64,ARGS[4])
    if length(ARGS) >= 5
        nbeg = parse(Int64,ARGS[5])
        nend = parse(Int64,ARGS[6])
    else
        nbeg = 1
        nend = Inf
    end
else
    filename = "95-103-wannier"
    N1 = 14
    N2 = 14
    N3 = 1
    nbeg = 1
    nend = Inf
end

nband,nntot = wannierize.read_parameters(filename,N1,N2,N3)
if nend == Inf
    nend = nband
end
println("$nband bands, wannierizing bands $nbeg:$nend, $N1 x $N2 x $N3 grid, $nntot neighbors")
wannierize.make_wannier(nband,N1,N2,N3,nntot,filename, nbeg, nend)
