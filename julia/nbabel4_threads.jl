
module NB

using Printf
using DelimitedFiles

struct Particle
  x :: Float64
  y :: Float64
  z :: Float64
  w :: Float64
end
Particle(x,y,z) = Particle(x,y,z,0)
norm2(p:: Particle) = p.x^2 + p.y^2 + p.z^2 + p.w^2
norm(p:: Particle) = sqrt(norm2(p))
import Base: +, -, *, zero
-(p1::Particle, p2::Particle) = Particle(p1.x-p2.x,p1.y-p2.y,p1.z-p2.z,p1.w-p2.w)
+(p1::Particle, p2::Particle) = Particle(p1.x+p2.x,p1.y+p2.y,p1.z+p2.z,p1.w+p2.w)
*(c::Real, p1::Particle) = Particle(c*p1.x,c*p1.y,c*p1.z,c*p1.w)
*(p1::Particle, c::Real) = c*p1
zero(T::Type{Particle}) = Particle(0,0,0,0)

function NBabel(fname::String; tend = 10., dt = 0.001, show=false)

    if show
	    println("Reading file : $fname")
    end

    mass, pos, vel = read_ICs(fname)

    return NBabelCalcs(mass, pos, vel, tend=tend, dt=dt, show=show)
end

function NBabelCalcs(mass, pos, vel; tend = 10., dt = 0.001, show=false)
    nthreads = Threads.nthreads()
    acc_parallel = Matrix{eltype(vel)}(undef,length(vel),nthreads)
    acc = compute_acceleration!(pos, mass, acc_parallel)
    last_acc = copy(acc)

    Ekin, Epot = compute_energy(pos, vel, mass)
    Etot_ICs = Ekin + Epot

    t = 0.0
    nstep = 0

    while t < tend

        update_positions!(pos, vel, acc, dt)

        last_acc .= acc

        acc = compute_acceleration!(pos, mass, acc_parallel)

        update_velocities!(vel, acc, last_acc, dt)
        
        t += dt
        nstep += 1

        if show && nstep%100 == 0

            Ekin, Epot = compute_energy(pos, vel, mass)
            Etot = Ekin + Epot
            dE = (Etot - Etot_ICs)/Etot_ICs

            @printf "t = %g, Etot=%g, Ekin=%g, Epot=%g, dE=%g \n" t Etot Ekin Epot dE
        end
    end

    Ekin, Epot = compute_energy(pos, vel, mass)
    Etot = Ekin + Epot
    return Ekin, Epot, Etot
end

function update_positions!(pos, vel, acc, dt)
    for i in eachindex(pos)
        pos[i] = (0.5 * acc[i] * dt + vel[i])*dt + pos[i]
    end
    nothing
end

function update_velocities!(vel, acc, last_acc, dt)
    for i in eachindex(vel)
        vel[i] = vel[i] + 0.5 * dt * (acc[i] + last_acc[i])
    end
    nothing
end

#
#Force calculation.
#
function compute_acceleration!(pos, mass, acc)
    nthreads = Threads.nthreads()
    N = length(pos)
    @inbounds for i in 1:N
      for j in 1:nthreads
        acc[i,j] = zero(eltype(acc))
      end
    end
    @inbounds Threads.@threads for i = 1:N-1
        id = Threads.threadid()
        @simd for j = i+1:N
            dr = pos[i] - pos[j]
            rinv3 = 1/norm(dr)^3
            acc[i,id] = acc[i,id] - mass[i] * rinv3 * dr
            acc[j,id] = acc[j,id] + mass[j] * rinv3 * dr
        end
    end
    @inbounds for i in 1:N
      for j in 2:nthreads
        acc[i,1] += acc[i,j]
      end
    end
    return @view acc[:,1]
end


# Kinetic and potential energy.
@inbounds function compute_energy(pos, vel, mass)
    N = length(vel)

    Ekin = 0.0

    for i = 1:N
        Ekin += 0.5 * mass[i] * norm2(vel[i])
    end

    nthreads = Threads.nthreads()
    Epot = zeros(nthreads)

    @inbounds Threads.@threads for i = 1:N-1
        id = Threads.threadid()
        @simd for j = i+1:N
            dr = pos[i] - pos[j]
            rinv = 1/norm(dr)
            Epot[id] -= mass[i] * mass[j] * rinv
        end
    end

    return Ekin, sum(Epot)
end

function read_ICs(fname::String)

    ICs = readdlm(fname)

    N = size(ICs,1)

    pos = Vector{Particle}(undef, N)
    vel = Vector{Particle}(undef, N)

    mass = Vector{Float64}(undef,N)
    mass .= ICs[:, 2]

    for i in axes(ICs, 1)
        pos[i] = Particle(ICs[i, 3], ICs[i, 4], ICs[i, 5])
    end

    for i in axes(ICs, 1)
        vel[i] = Particle(ICs[i, 6], ICs[i, 7], ICs[i, 8])
    end

    return mass, pos, vel
end

export NBabel

end

#using .NB
#NBabel(ARGS[1], show=parse(Bool,ARGS[2]))
